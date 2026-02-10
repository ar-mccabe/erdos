import SwiftUI

struct PlanView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var editContent = ""
    @State private var planContent = ""
    @State private var planFilePath: String?
    @State private var autoRefreshTimer: Timer?
    @State private var planLaunchTime: Date?
    /// Path of the detected plan file in ~/.claude/plans/ (locked on once found)
    @State private var detectedClaudePlanPath: String?
    /// Last modification date of the detected plan file (to know when it stabilizes)
    @State private var detectedPlanLastModified: Date?
    /// How many consecutive polls the detected plan file hasn't changed
    @State private var stablePolls: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                // Left: action buttons
                if planContent.isEmpty && experiment.worktreePath != nil {
                    Button {
                        launchResearchPlan()
                    } label: {
                        Label("Research Plan", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !planContent.isEmpty && experiment.worktreePath != nil {
                    Button {
                        launchUpdatePlan()
                    } label: {
                        Label("Update Plan", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                if planLaunchTime != nil {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Watching...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Stop") {
                        planLaunchTime = nil
                        detectedClaudePlanPath = nil
                        detectedPlanLastModified = nil
                        stablePolls = 0
                        autoRefreshTimer?.invalidate()
                        autoRefreshTimer = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                Spacer()

                // Right: path, edit, refresh
                if let path = planFilePath {
                    CopyableLabel(
                        text: path,
                        display: path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                        font: .caption2,
                        color: .quaternary
                    )

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

                if planLaunchTime == nil {
                    Button {
                        Task { await loadPlan() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Refresh")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

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
        launchClaudeWithPrompt(buildResearchPrompt(), label: "Research Plan")
    }

    private func launchUpdatePlan() {
        launchClaudeWithPrompt(buildUpdatePrompt(), label: "Update Plan")
    }

    private func launchClaudeWithPrompt(_ prompt: String, label: String) {
        // Write prompt to temp file to avoid shell quoting issues
        let tmpFile = NSTemporaryDirectory() + "erdos-prompt-\(UUID().uuidString).txt"
        try? prompt.write(toFile: tmpFile, atomically: true, encoding: .utf8)

        let model = ErdosSettings.shared.defaultModel
        let command = "claude \"$(cat '\(tmpFile)')\" --model \(model) --permission-mode plan --allowed-tools 'Read,Glob,Grep,WebSearch,WebFetch,Task,\"Bash(git log:*)\",\"Bash(git diff:*)\",\"Bash(git show:*)\",\"Bash(git status:*)\",\"Bash(git branch:*)\",\"Bash(git -C:*)\"'; rm -f '\(tmpFile)'"

        // Record launch time so we can find the plan file Claude creates in ~/.claude/plans/
        planLaunchTime = Date()
        detectedClaudePlanPath = nil
        detectedPlanLastModified = nil
        stablePolls = 0

        NotificationCenter.default.post(
            name: .launchClaude,
            object: nil,
            userInfo: [
                "command": command,
                "label": label,
                "experimentId": experiment.id.uuidString,
            ]
        )

        appState.statusInference.onResearchLaunched(experiment: experiment, context: modelContext)

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
        4. Create a detailed implementation plan — you are in plan mode, so write your plan and use ExitPlanMode when done

        The plan should include:
        - Summary of findings from codebase exploration
        - Proposed approach with rationale
        - Step-by-step implementation phases
        - Key files to modify or create
        - Risks and open questions
        - Estimated complexity
        """)

        return parts.joined(separator: "\n")
    }

    private func buildUpdatePrompt() -> String {
        var parts: [String] = []

        parts.append("You are updating an existing implementation plan. The codebase has changed since this plan was written. Your goal is to re-explore the codebase and revise the plan to reflect the current state.")

        parts.append("")
        parts.append("## Experiment: \(experiment.title)")

        if !experiment.hypothesis.isEmpty {
            parts.append("")
            parts.append("## Hypothesis")
            parts.append(experiment.hypothesis)
        }

        parts.append("")
        parts.append("## Current Plan")
        parts.append(planContent)

        parts.append("")
        parts.append("## Instructions")
        parts.append("""
        1. Read the current plan above carefully
        2. Explore the codebase to understand what has changed since the plan was written
        3. Run `git log --oneline -20` to see recent commits
        4. Revise the plan to account for the current state of the codebase
        5. Keep the same intent and goals — just update the approach, file references, and steps to match reality
        6. You are in plan mode — write your updated plan and use ExitPlanMode when done
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
            planContent = ""
            return
        }

        let planMdPath = (worktree as NSString).appendingPathComponent("PLAN.md")

        // If actively waiting for a plan from Claude, check ~/.claude/plans/ first
        if let launchTime = planLaunchTime {
            if let (path, modified, content) = findClaudePlanFile(after: launchTime) {
                if detectedClaudePlanPath == nil {
                    // First time seeing this plan file — lock onto it
                    detectedClaudePlanPath = path
                    detectedPlanLastModified = modified
                    stablePolls = 0
                } else if modified == detectedPlanLastModified {
                    // File hasn't changed since last poll
                    stablePolls += 1
                } else {
                    // File was updated — reset stability counter
                    detectedPlanLastModified = modified
                    stablePolls = 0
                }

                // After 3 stable polls (~9s of no changes), consider it final
                if stablePolls >= 3 {
                    try? content.write(toFile: planMdPath, atomically: true, encoding: .utf8)
                    planContent = content
                    planFilePath = planMdPath
                    planLaunchTime = nil
                    detectedClaudePlanPath = nil
                    detectedPlanLastModified = nil
                    stablePolls = 0
                    autoRefreshTimer?.invalidate()
                    autoRefreshTimer = nil
                    appState.statusInference.onPlanDetected(experiment: experiment, context: modelContext)
                    return
                }
            }
            // Keep polling — don't fall through to stop the timer
            return
        }

        // No active session — just load PLAN.md from worktree
        if FileManager.default.fileExists(atPath: planMdPath),
           let content = try? String(contentsOfFile: planMdPath, encoding: .utf8),
           !content.isEmpty {
            planContent = content
            planFilePath = planMdPath
            autoRefreshTimer?.invalidate()
            autoRefreshTimer = nil
            return
        }

        planContent = ""
    }

    /// Scan ~/.claude/plans/ for the newest .md file modified after the given date.
    /// Returns (path, modificationDate, content) or nil.
    private func findClaudePlanFile(after launchTime: Date) -> (String, Date, String)? {
        let plansDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/plans")
        let fm = FileManager.default

        // If we've already locked onto a file, just check that one
        if let locked = detectedClaudePlanPath {
            guard let attrs = try? fm.attributesOfItem(atPath: locked),
                  let modified = attrs[.modificationDate] as? Date,
                  let content = try? String(contentsOfFile: locked, encoding: .utf8),
                  !content.isEmpty else { return nil }
            return (locked, modified, content)
        }

        // Otherwise scan for the newest file after launch time
        guard let files = try? fm.contentsOfDirectory(atPath: plansDir) else { return nil }

        var bestFile: String?
        var bestDate: Date = launchTime

        for file in files where file.hasSuffix(".md") {
            let fullPath = (plansDir as NSString).appendingPathComponent(file)
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  let modified = attrs[.modificationDate] as? Date,
                  modified > bestDate else { continue }
            bestDate = modified
            bestFile = fullPath
        }

        guard let path = bestFile,
              let content = try? String(contentsOfFile: path, encoding: .utf8),
              !content.isEmpty else { return nil }

        return (path, bestDate, content)
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
