import SwiftUI
import SwiftData

struct ResearchView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var prompt = ""
    @State private var streamingOutput = ""
    @State private var isRunning = false
    @State private var statusMessage = ""
    @State private var error: String?
    @State private var currentSessionId: String?
    @State private var claudeService = ClaudeService()
    @State private var permissionMode: ResearchPermissionMode = .readAndWeb
    @State private var startTime: Date?
    @State private var elapsedSeconds = 0
    @State private var timer: Timer?

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

                            if isRunning {
                                runningIndicator
                            }

                            Color.clear.frame(height: 1).id("bottom")
                        }

                        if let error {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .foregroundStyle(.red)
                            }
                            .font(.caption)
                            .padding(8)
                            .background(.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding()
                }
                .onChange(of: streamingOutput) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: statusMessage) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            Divider()

            // Status bar when running
            if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(elapsedSeconds)s")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.blue.opacity(0.05))

                Divider()
            }

            // Input area
            VStack(spacing: 6) {
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
                            statusMessage = ""
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Stop research session")
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

                HStack(spacing: 4) {
                    Picker("Permissions", selection: $permissionMode) {
                        ForEach(ResearchPermissionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                    .controlSize(.small)
                    .disabled(isRunning)

                    Text(permissionMode.description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
            }
            .padding(12)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var runningIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(statusMessage.isEmpty ? "Starting Claude..." : statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(.top, 8)
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
        statusMessage = "Starting Claude..."
        startTime = Date()
        elapsedSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if let start = startTime {
                    elapsedSeconds = Int(Date().timeIntervalSince(start))
                }
            }
        }

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
            statusMessage = "Waiting for Claude to respond..."

            var receivedFirstChunk = false

            for try await chunk in claudeService.streamResearch(
                prompt: fullPrompt,
                workingDirectory: workingDir.isEmpty ? nil : workingDir,
                resumeSessionId: currentSessionId,
                permissionMode: permissionMode,
                maxBudget: 2.0
            ) {
                switch chunk {
                case .text(let text):
                    if !receivedFirstChunk {
                        receivedFirstChunk = true
                        statusMessage = "Claude is responding..."
                    }
                    streamingOutput += text
                case .sessionId(let id):
                    currentSessionId = id
                    session.sessionId = id
                    statusMessage = "Session connected (id: \(id.prefix(8))...)"
                case .result(let cost, let input, let output):
                    session.costUSD = cost
                    session.inputTokens = input
                    session.outputTokens = output
                    statusMessage = "Completed — $\(String(format: "%.2f", cost))"
                case .error(let msg):
                    error = msg
                    statusMessage = "Error occurred"
                }
            }

            session.status = .completed
            session.endedAt = Date()
        } catch {
            session.status = .errored
            session.endedAt = Date()
            self.error = error.localizedDescription
            statusMessage = "Session errored"
        }

        let endEvent = TimelineEvent(
            eventType: .sessionEnded,
            summary: "Research session ended. Cost: $\(String(format: "%.2f", session.costUSD))"
        )
        endEvent.experiment = experiment
        modelContext.insert(endEvent)

        appState.updateStats(context: modelContext)
        isRunning = false
        startTime = nil
        statusMessage = ""
        timer?.invalidate()
        timer = nil
    }
}
