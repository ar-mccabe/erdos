import SwiftUI
import SwiftData

struct ResearchView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var prompt = ""
    @State private var streamingOutput = ""
    @State private var isRunning = false
    @State private var error: String?
    @State private var currentSessionId: String?
    @State private var claudeService = ClaudeService()

    var body: some View {
        VStack(spacing: 0) {
            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if streamingOutput.isEmpty && !isRunning {
                            emptyState
                        } else {
                            Text(streamingOutput)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("bottom")
                        }

                        if let error {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                    .padding()
                }
                .onChange(of: streamingOutput) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            Divider()

            // Input area
            HStack(spacing: 8) {
                TextField("Research prompt...", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        if !prompt.isEmpty && !isRunning {
                            Task { await startResearch() }
                        }
                    }

                if isRunning {
                    Button {
                        claudeService.cancel()
                        isRunning = false
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button {
                        Task { await startResearch() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(prompt.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(12)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Start a research session")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Enter a prompt to have Claude explore this experiment's hypothesis and codebase.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let lastSession = experiment.sessions.last(where: { $0.sessionId != nil }) {
                Button("Resume last session") {
                    currentSessionId = lastSession.sessionId
                    prompt = "Continue where you left off."
                    Task { await startResearch() }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func startResearch() async {
        let currentPrompt = prompt
        prompt = ""
        isRunning = true
        error = nil

        // Create session record
        let session = ClaudeSession(purpose: currentPrompt, model: "sonnet")
        session.status = .running
        session.startedAt = Date()
        session.experiment = experiment
        if let resumeId = currentSessionId {
            session.sessionId = resumeId
        }
        modelContext.insert(session)

        let event = TimelineEvent(eventType: .sessionStarted, summary: "Research session started: \(currentPrompt.prefix(80))")
        event.experiment = experiment
        modelContext.insert(event)

        let workingDir = experiment.worktreePath ?? experiment.repoPath

        do {
            let fullPrompt: String
            if experiment.hypothesis.isEmpty {
                fullPrompt = currentPrompt
            } else {
                fullPrompt = "Context - Experiment: \(experiment.title). Hypothesis: \(experiment.hypothesis)\n\n\(currentPrompt)"
            }

            streamingOutput += "\n--- Research: \(currentPrompt) ---\n\n"

            for try await chunk in claudeService.streamResearch(
                prompt: fullPrompt,
                workingDirectory: workingDir.isEmpty ? nil : workingDir,
                resumeSessionId: currentSessionId,
                maxBudget: 2.0
            ) {
                switch chunk {
                case .text(let text):
                    streamingOutput += text
                case .sessionId(let id):
                    currentSessionId = id
                    session.sessionId = id
                case .result(let cost, let input, let output):
                    session.costUSD = cost
                    session.inputTokens = input
                    session.outputTokens = output
                case .error(let msg):
                    error = msg
                }
            }

            session.status = .completed
            session.endedAt = Date()
        } catch {
            session.status = .errored
            session.endedAt = Date()
            self.error = error.localizedDescription
        }

        let endEvent = TimelineEvent(
            eventType: .sessionEnded,
            summary: "Research session ended. Cost: $\(String(format: "%.2f", session.costUSD))"
        )
        endEvent.experiment = experiment
        modelContext.insert(endEvent)

        appState.updateStats(context: modelContext)
        isRunning = false
    }
}
