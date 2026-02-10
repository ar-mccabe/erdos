import SwiftUI
import SwiftData
import AppKit

struct TaskDraftView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    enum TaskAction { case draftTask, draftUpdate }

    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var rawOutput = ""
    @State private var isRunning = false
    @State private var statusMessage = ""
    @State private var error: String?
    @State private var claudeService = ClaudeService()
    @State private var currentAction: TaskAction = .draftTask
    @State private var startTime: Date?
    @State private var elapsedSeconds = 0
    @State private var timer: Timer?
    @State private var draftFilePath: String?

    private var hasPriorDraft: Bool { draftFilePath != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button {
                    currentAction = .draftTask
                    Task { await runDraft() }
                } label: {
                    Label("Draft Task", systemImage: "doc.text.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRunning)

                if hasPriorDraft {
                    Button {
                        currentAction = .draftUpdate
                        Task { await runDraft() }
                    } label: {
                        Label("Draft Update", systemImage: "arrow.uturn.up")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(isRunning)
                }

                if isRunning {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("\(elapsedSeconds)s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("Stop") {
                            claudeService.cancel()
                            isRunning = false
                            statusMessage = ""
                            cleanupTimer()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }

                Spacer()

                if let path = draftFilePath {
                    CopyableLabel(
                        text: path,
                        display: path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                        font: .caption2,
                        color: .quaternary
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            // Content
            if rawOutput.isEmpty && !isRunning && !hasPriorDraft {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !draftTitle.isEmpty {
                                titleCard
                            }

                            if !draftBody.isEmpty {
                                bodyCard
                            }

                            if isRunning && draftTitle.isEmpty && draftBody.isEmpty {
                                Text(rawOutput)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if isRunning {
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

                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding()
                    }
                    .onChange(of: rawOutput) { _, _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .task { loadExistingDraft() }
    }

    // MARK: - Cards

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Title")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                CopyButton(text: draftTitle, label: "Copy Title")
            }
            Text(draftTitle)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Body")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                CopyButton(text: draftBody, label: "Copy Body")
                CopyButton(text: "# \(draftTitle)\n\n\(draftBody)", label: "Copy All")
            }
            MarkdownContentView(content: draftBody)
                .frame(minHeight: 200)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Draft a Task")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Generate a Convictional task description from this experiment's plan, git history, and timeline. Copy-paste the result into Convictional.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button {
                currentAction = .draftTask
                Task { await runDraft() }
            } label: {
                Label("Draft Task", systemImage: "doc.text.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Draft Execution

    private func runDraft() async {
        isRunning = true
        error = nil
        rawOutput = ""
        draftTitle = ""
        draftBody = ""
        statusMessage = "Gathering context..."
        startTime = Date()
        elapsedSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if let start = startTime {
                    elapsedSeconds = Int(Date().timeIntervalSince(start))
                }
            }
        }

        let workingDir = experiment.worktreePath ?? experiment.repoPath

        do {
            let prompt: String
            switch currentAction {
            case .draftTask:
                prompt = await buildDraftTaskPrompt()
            case .draftUpdate:
                prompt = await buildDraftUpdatePrompt()
            }

            statusMessage = "Waiting for Claude..."

            for try await chunk in claudeService.streamResearch(
                prompt: prompt,
                workingDirectory: workingDir.isEmpty ? nil : workingDir,
                model: "sonnet",
                permissionMode: .readOnly,
                maxBudget: 0.5,
                maxTurns: 2
            ) {
                switch chunk {
                case .text(let text):
                    rawOutput += text
                    statusMessage = "Claude is writing..."
                    parseDraftOutput()
                case .sessionId:
                    break
                case .result(let cost, _, _):
                    statusMessage = "Completed — $\(String(format: "%.4f", cost))"
                case .error(let msg):
                    error = msg
                    statusMessage = "Error occurred"
                }
            }

            // Final parse
            parseDraftOutput()

            // Save to file
            saveDraft()

            // Record timeline event
            let eventType: EventType = currentAction == .draftTask ? .taskDrafted : .taskUpdateDrafted
            let summary = currentAction == .draftTask
                ? "Task drafted: \(draftTitle.prefix(80))"
                : "Task update drafted"
            let event = TimelineEvent(eventType: eventType, summary: summary)
            event.experiment = experiment
            modelContext.insert(event)

            appState.updateStats(context: modelContext)
        } catch {
            self.error = error.localizedDescription
            statusMessage = "Error occurred"
        }

        isRunning = false
        cleanupTimer()
    }

    // MARK: - Prompt Building

    private func buildDraftTaskPrompt() async -> String {
        var parts: [String] = []

        parts.append("""
        You are writing a task description for a team project tracker (Convictional). Write in direct, casual, first-person tone. Not corporate speak.

        Structure varies by type:
        - Implementation tasks: problem context → hypothesis/approach → scope/footprint
        - Research tasks: background → hypothesis → approach → what success looks like

        Use markdown: headers, bullet points, inline links where relevant. Use <br /> for spacing between sections.
        Match length to complexity — simple tasks get 1-3 sentences, research tasks get detailed multi-section writeups.

        Output format — you MUST use exactly these two headers:
        ## Title
        (A concise task title on one line)

        ## Body
        (The full task description in markdown)
        """)

        // Few-shot examples
        parts.append("")
        parts.append("--- EXAMPLE 1 (implementation task) ---")
        parts.append("""
        ## Title
        Goals Custom View - use recent activity context

        ## Body
        The goals custom view organizes a user's inbox by mapping emails to their organization's goals using an LLM.
        Currently the LLM only receives basic goal metadata (title, target date, owner, team) plus email thread previews —
        it has no context about what's actually happening with each goal.

        The hypothesis is that including recent goal activity (comments, status changes, periodic updates) gives the LLM
        much richer signal for mapping emails to the right goals, and helps surface emails that are timely given current
        goal state. For example, if someone just commented on a goal about a vendor contract, an email from that vendor
        should rank higher for that goal.

        The approach enriches the organize-by-goals prompt with a "Recent Activity" section per goal. Three types of
        activity are batch-fetched (3 total queries regardless of goal count) and formatted concisely:

        * Goal comments — direct discussion, people's names, topics, action items that can match email senders/subjects
        * Goal events — status changes, metric updates, completions showing momentum
        * Goal update submissions — periodic status reports with Q&A responses

        Per-goal limits and content truncation keep token usage reasonable (~50-100 tokens per active goal). Goals with no
        recent activity (14-day lookback) show no activity section, which is itself signal to the LLM that the goal may be
        less active.

        Minimal footprint: 1 new helper function, 1 prompt template change, 2 files modified, no new models or migrations.
        """)

        parts.append("")
        parts.append("--- EXAMPLE 2 (research task) ---")
        parts.append("""
        ## Title
        [Research] LoRA Cassettes for Embedding Models

        ## Body
        # LoRA Cassettes for Continual Learning

        ### 1. High Entropy Entities

        One of our biggest retrieval challenges lies with **High-Entropy Entities (HEEs)**. These aren't necessarily rare, unknown terms. Often, they are entities that appear *everywhere* in our corpus, creating a sea of noise that makes finding the truly important documents difficult.

        <br />

        Consider a project name like `"Decide"`. It's mentioned in hundreds of Github messages, emails, specs, and meeting notes. The challenge isn't just finding documents that contain this phrase; it's finding the **canonical technical spec** or the **critical decision-making thread** among a hundred low-signal, conversational mentions.

        ### 2. Idea

        > **My central hypothesis is this: Instead of manually structuring our internal knowledge to make it searchable, or defining structured rules for an LLM to do it, we can empower our embedding model to learn and consolidate this knowledge implicitly within its own weights, in a completely self-supervised way.**

        ### 3. Proposed Approach: LoRA Cassettes

        The strategy is to create a retrieval system that is constantly learning.

        1. **Frozen Base:** We will start with a powerful, pre-trained base embedding model. This model remains frozen, providing a stable foundation for retrieval.
        2. **Episodic Training:** On a periodic basis (e.g., quarterly), we will automatically mine all new documents and activity created in that period for training pairs.
        3. **(MVP) Create a "Global Adapter":** We will then train a single, small LoRA adapter on this new data.
        4. **Two-Stage Retrieval:** When a user searches, first retrieve candidates with simpler search, then re-rank with the adapted model.

        <br />

        ### 4. What Success Looks Like (POC Goals)

        * **Primary Metric:** Achieve a **+10% improvement in NDCG@10** on our benchmark query set, especially for queries involving high-entropy entities.
        * **Freshness:** Demonstrate significantly better performance on queries related to proprietary knowledge or jargon.
        * **Stability:** Ensure the model does not get worse at finding older, evergreen information.
        * **Efficiency:** Prove that the episodic training process is computationally cheap and can be fully automated.
        """)

        parts.append("")
        parts.append("--- NOW DRAFT A TASK FOR THIS EXPERIMENT ---")
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

        // Plan content
        if let worktree = experiment.worktreePath {
            let planPath = (worktree as NSString).appendingPathComponent("PLAN.md")
            if let planContent = try? String(contentsOfFile: planPath, encoding: .utf8), !planContent.isEmpty {
                parts.append("")
                parts.append("## Implementation Plan (PLAN.md)")
                let truncated = planContent.count > 3000 ? String(planContent.prefix(3000)) + "\n\n[...truncated]" : planContent
                parts.append(truncated)
            }
        }

        // Git log
        let gitLog = await gatherGitLog(since: nil)
        if !gitLog.isEmpty {
            parts.append("")
            parts.append("## Git History (branch commits)")
            parts.append(gitLog)
        }

        // Recent timeline
        let timelineText = gatherTimeline(since: nil, limit: 20)
        if !timelineText.isEmpty {
            parts.append("")
            parts.append("## Recent Timeline Events")
            parts.append(timelineText)
        }

        parts.append("")
        parts.append("Now write the task. Use ## Title and ## Body headers. Match the tone and style of the examples above.")

        return parts.joined(separator: "\n")
    }

    private func buildDraftUpdatePrompt() async -> String {
        var parts: [String] = []

        parts.append("""
        You are writing a progress update comment for a task on a team project tracker (Convictional). Write in direct, casual, first-person tone. Not corporate speak.

        This is an update comment, not a new task description. Summarize what's happened since the task was created — what was done, what changed, what's next. Keep it concise but informative.

        Use markdown: bullet points, inline code, links where relevant.

        Output format — you MUST use exactly these two headers:
        ## Title
        (A short summary line for the update, e.g. "Progress update: streaming UI complete")

        ## Body
        (The update comment in markdown)
        """)

        // Few-shot example of an update
        parts.append("")
        parts.append("--- EXAMPLE UPDATE ---")
        parts.append("""
        ## Title
        Progress update: pair mining pipeline complete

        ## Body
        Pair mining pipeline is working end-to-end. A few notes:

        * Built the self-supervised pair mining for meetings and emails — generates ~12k training pairs from 3 months of data
        * Training a global LoRA adapter takes ~8 minutes on a single A10G, well within the "cheap" target
        * Initial NDCG@10 numbers look promising (+6-8%) but need to run the full benchmark before getting excited
        * Haven't touched the multi-adapter routing yet — keeping that out of scope for now

        Next up: running the full benchmark suite and writing the comparison report.
        """)

        parts.append("")
        parts.append("--- NOW DRAFT AN UPDATE FOR THIS EXPERIMENT ---")
        parts.append("")
        parts.append("## Experiment: \(experiment.title)")

        // Current task draft content
        if let worktree = experiment.worktreePath {
            let draftPath = (worktree as NSString).appendingPathComponent("TASK-DRAFT.md")
            if let content = try? String(contentsOfFile: draftPath, encoding: .utf8), !content.isEmpty {
                parts.append("")
                parts.append("## Original Task Description")
                parts.append(content)
            }
        }

        // Find last taskDrafted event for "since" queries
        let lastDraftDate = experiment.timeline
            .filter { $0.eventType == .taskDrafted || $0.eventType == .taskUpdateDrafted }
            .sorted { $0.createdAt < $1.createdAt }
            .last?.createdAt

        // Git log since last draft
        let gitLog = await gatherGitLog(since: lastDraftDate)
        if !gitLog.isEmpty {
            parts.append("")
            parts.append("## Git Commits Since Last Draft")
            parts.append(gitLog)
        }

        // Timeline since last draft
        let timelineText = gatherTimeline(since: lastDraftDate, limit: 20)
        if !timelineText.isEmpty {
            parts.append("")
            parts.append("## Timeline Events Since Last Draft")
            parts.append(timelineText)
        }

        parts.append("")
        parts.append("Now write the update. Use ## Title and ## Body headers. Match the tone of the example above.")

        return parts.joined(separator: "\n")
    }

    // MARK: - Context Gathering

    private func gatherGitLog(since: Date?) async -> String {
        guard let worktree = experiment.worktreePath,
              let baseBranch = experiment.baseBranch else { return "" }

        var args = ["log", "--oneline", "\(baseBranch)..HEAD"]

        if let since {
            let formatter = ISO8601DateFormatter()
            args.insert(contentsOf: ["--since", formatter.string(from: since)], at: 1)
        }

        args.append(contentsOf: ["-n", "50"])

        guard let result = try? await ProcessRunner.shared.run(
            "/usr/bin/git", arguments: args, currentDirectory: worktree
        ), result.succeeded, !result.stdout.isEmpty else { return "" }

        return result.stdout
    }

    private func gatherTimeline(since: Date?, limit: Int) -> String {
        let events = experiment.timeline
            .filter { event in
                if let since { return event.createdAt > since }
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)

        guard !events.isEmpty else { return "" }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        return events.map { event in
            "- [\(formatter.string(from: event.createdAt))] \(event.eventType.label): \(event.summary)"
        }.joined(separator: "\n")
    }

    // MARK: - Output Parsing

    private func parseDraftOutput() {
        let text = rawOutput

        // Find ## Title
        if let titleRange = text.range(of: "## Title") {
            let afterTitle = text[titleRange.upperBound...]
            // Find the next ## header or end of string
            let titleEnd = afterTitle.range(of: "\n## ")?.lowerBound ?? afterTitle.endIndex
            let titleContent = afterTitle[..<titleEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !titleContent.isEmpty {
                draftTitle = titleContent
            }
        }

        // Find ## Body
        if let bodyRange = text.range(of: "## Body") {
            let afterBody = text[bodyRange.upperBound...]
            // Body goes to end of output (it's the last section)
            let bodyContent = afterBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bodyContent.isEmpty {
                draftBody = bodyContent
            }
        }
    }

    // MARK: - Persistence

    private func loadExistingDraft() {
        guard let worktree = experiment.worktreePath else { return }
        let path = (worktree as NSString).appendingPathComponent("TASK-DRAFT.md")
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8),
              !content.isEmpty else { return }

        draftFilePath = path
        rawOutput = content
        parseDraftOutput()

        // If parsing failed, show raw content as body
        if draftTitle.isEmpty && draftBody.isEmpty {
            draftBody = content
        }
    }

    private func saveDraft() {
        guard let worktree = experiment.worktreePath else { return }
        let path = (worktree as NSString).appendingPathComponent("TASK-DRAFT.md")

        let content: String
        if !draftTitle.isEmpty && !draftBody.isEmpty {
            content = "## Title\n\n\(draftTitle)\n\n## Body\n\n\(draftBody)\n"
        } else {
            content = rawOutput
        }

        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        draftFilePath = path
    }

    private func cleanupTimer() {
        startTime = nil
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - CopyButton

private struct CopyButton: View {
    let text: String
    let label: String
    @State private var showCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeInOut(duration: 0.15)) { showCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
            }
        } label: {
            if showCopied {
                Label("Copied", systemImage: "checkmark")
                    .foregroundStyle(.green)
            } else {
                Label(label, systemImage: "doc.on.doc")
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}
