import SwiftUI

struct PlanView: View {
    @Bindable var experiment: Experiment
    @State private var isEditing = false
    @State private var editContent = ""
    @State private var planContent = ""
    @State private var planFilePath: String?
    @State private var autoRefreshTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                if planContent.isEmpty && experiment.worktreePath != nil {
                    Button {
                        launchResearchPlan()
                    } label: {
                        Label("Research Plan", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                if planFilePath != nil {
                    Button(isEditing ? "Preview" : "Edit") {
                        if isEditing {
                            savePlan()
                        } else {
                            editContent = planContent
                        }
                        isEditing.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                Button("Refresh") {
                    Task { await loadPlan() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if isEditing {
                TextEditor(text: $editContent)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
            } else if planContent.isEmpty {
                emptyState
            } else {
                MarkdownContentView(content: planContent)
            }
        }
        .task { await loadPlan() }
        .onDisappear {
            autoRefreshTimer?.invalidate()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No Plan Yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            if experiment.worktreePath != nil {
                Text("Click 'Research Plan' to have Claude explore the codebase and create an implementation plan based on your hypothesis.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                Button {
                    launchResearchPlan()
                } label: {
                    Label("Research Plan", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Create a worktree for this experiment first, then use Research Plan to generate one.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func launchResearchPlan() {
        let prompt = buildResearchPrompt()

        // Write prompt to temp file to avoid shell quoting issues
        let tmpFile = NSTemporaryDirectory() + "erdos-prompt-\(UUID().uuidString).txt"
        try? prompt.write(toFile: tmpFile, atomically: true, encoding: .utf8)

        // Launch interactive claude with the prompt as first message
        let model = ErdosSettings.shared.defaultModel
        let command = "claude \"$(cat '\(tmpFile)')\" --model \(model); rm -f '\(tmpFile)'"

        NotificationCenter.default.post(
            name: .launchClaude,
            object: nil,
            userInfo: ["command": command, "label": "Research Plan"]
        )

        // Start auto-refreshing to pick up PLAN.md when Claude writes it
        startAutoRefresh()
    }

    private func buildResearchPrompt() -> String {
        var parts: [String] = []

        parts.append("You are researching an experiment idea. Your goal is to explore the codebase, understand the relevant architecture, and create a detailed implementation plan.")

        parts.append("")
        parts.append("## Experiment: \(experiment.title)")

        if !experiment.hypothesis.isEmpty {
            parts.append("")
            parts.append("## Hypothesis")
            parts.append(experiment.hypothesis)
        }

        if !experiment.detail.isEmpty {
            parts.append("")
            parts.append("## Additional Context")
            parts.append(experiment.detail)
        }

        parts.append("")
        parts.append("## Instructions")
        parts.append("""
        1. Explore the codebase to understand the current architecture and relevant code
        2. Identify the key files, modules, and patterns that relate to this experiment
        3. Search the web if you need context on libraries, APIs, or approaches
        4. Create a detailed implementation plan and write it to PLAN.md in the current directory

        The PLAN.md should include:
        - Summary of findings from codebase exploration
        - Proposed approach with rationale
        - Step-by-step implementation phases
        - Key files to modify or create
        - Risks and open questions
        - Estimated complexity
        """)

        return parts.joined(separator: "\n")
    }

    private func startAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                await loadPlan()
            }
        }
    }

    private func loadPlan() async {
        guard let worktree = experiment.worktreePath else {
            planContent = experiment.detail
            return
        }

        // Only look for PLAN.md — not CLAUDE.md/README.md which are repo docs
        let path = (worktree as NSString).appendingPathComponent("PLAN.md")
        if FileManager.default.fileExists(atPath: path),
           let content = try? String(contentsOfFile: path, encoding: .utf8),
           !content.isEmpty {
            planContent = content
            planFilePath = path
            autoRefreshTimer?.invalidate()
            autoRefreshTimer = nil
            return
        }

        planContent = ""
    }

    private func savePlan() {
        if let path = planFilePath {
            try? editContent.write(toFile: path, atomically: true, encoding: .utf8)
            planContent = editContent
        } else {
            experiment.detail = editContent
            planContent = editContent
        }
    }
}
