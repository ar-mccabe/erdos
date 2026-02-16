import SwiftUI
import SwiftData
import AppKit

struct TaskDraftView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    enum TaskAction { case draftTask, draftUpdate }

    // Transient streaming state (only used during generation)
    @State private var streamingTitle = ""
    @State private var streamingBody = ""
    @State private var rawOutput = ""
    @State private var isRunning = false
    @State private var statusMessage = ""
    @State private var error: String?
    @State private var claudeService = ClaudeService()
    @State private var currentAction: TaskAction = .draftTask
    @State private var startTime: Date?
    @State private var elapsedSeconds = 0
    @State private var timer: Timer?
    @State private var didMigrate = false

    private var hasOriginalTask: Bool { experiment.originalTask != nil }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if experiment.taskUpdateHistory.isEmpty && !isRunning {
                emptyState
            } else {
                feedView
            }
        }
        .task { migrateExistingDraft() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                currentAction = .draftTask
                Task { await runDraft() }
            } label: {
                Label(hasOriginalTask ? "Redraft Task" : "Draft Task", systemImage: "doc.text.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRunning)

            if hasOriginalTask {
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
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Feed

    private var feedView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(experiment.taskUpdateHistory) { update in
                        taskUpdateCard(update)
                    }

                    // Streaming card during generation
                    if isRunning {
                        streamingCard
                    }

                    if let error {
                        errorBanner(error)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .onChange(of: rawOutput) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: experiment.taskUpdates.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Task Update Card

    private func taskUpdateCard(_ update: TaskUpdate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Type badge
                Text(update.updateType == .original ? "Original Task" : "Update")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(update.updateType == .original ? Color.indigo.opacity(0.15) : Color.teal.opacity(0.15))
                    .foregroundStyle(update.updateType == .original ? .indigo : .teal)
                    .clipShape(Capsule())

                Text(update.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if update.costUSD > 0 {
                    Text("$\(String(format: "%.4f", update.costUSD))")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }

                Spacer()

                CopyButton(text: update.title, label: "Title")
                CopyButton(text: update.body, label: "Body")
                CopyButton(text: "# \(update.title)\n\n\(update.body)", label: "All")
            }

            Text(update.title)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)

            MarkdownContentView(content: update.body)
                .frame(minHeight: 100)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Streaming Card

    private var streamingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(currentAction == .draftTask ? "Original Task" : "Update")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())

                Text("Generating...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .italic()

                Spacer()
            }

            if !streamingTitle.isEmpty {
                Text(streamingTitle)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
            }

            if !streamingBody.isEmpty {
                MarkdownContentView(content: streamingBody)
                    .frame(minHeight: 100)
            }

            if streamingTitle.isEmpty && streamingBody.isEmpty && !rawOutput.isEmpty {
                Text(rawOutput)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(statusMessage.isEmpty ? "Starting Claude..." : statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.orange.opacity(0.2), lineWidth: 1)
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.red)
        }
        .font(.caption)
        .padding(8)
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Empty State

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
        streamingTitle = ""
        streamingBody = ""
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
            var totalCost: Double = 0

            switch currentAction {
            case .draftTask:
                let prompt = await buildDraftTaskPrompt()
                statusMessage = "Waiting for Claude..."
                totalCost = try await streamGeneration(prompt: prompt, workingDir: workingDir)

            case .draftUpdate:
                // Step 1: Extract context with Haiku
                statusMessage = "Step 1: Analyzing changes..."
                let extractionPrompt = await buildExtractionPrompt()
                var extractedSummary = ""
                var step1Cost: Double = 0

                for try await chunk in claudeService.streamResearch(
                    prompt: extractionPrompt,
                    workingDirectory: workingDir.isEmpty ? nil : workingDir,
                    model: "haiku",
                    permissionMode: .readOnly,
                    maxBudget: 1.5,
                    maxTurns: 20
                ) {
                    guard isRunning else { break }
                    switch chunk {
                    case .text(let text):
                        extractedSummary += text
                    case .result(let cost, _, _):
                        step1Cost = cost
                    case .sessionId:
                        break
                    case .error(let msg):
                        error = msg
                    }
                }

                guard isRunning else {
                    cleanupTimer()
                    return
                }

                // Step 2: Write update with Sonnet
                statusMessage = "Step 2: Writing update..."
                let updatePrompt = await buildDraftUpdatePrompt(extractedSummary: extractedSummary)
                let step2Cost = try await streamGeneration(prompt: updatePrompt, workingDir: workingDir)
                totalCost = step1Cost + step2Cost
            }

            // Final parse
            parseStreamingOutput()

            // Persist as TaskUpdate entity
            let updateType: TaskUpdateType = currentAction == .draftTask ? .original : .update
            let title = streamingTitle.isEmpty ? experiment.title : streamingTitle
            let body = streamingBody.isEmpty ? rawOutput : streamingBody

            // If redrafting original, remove the old one
            if currentAction == .draftTask, let existing = experiment.originalTask {
                modelContext.delete(existing)
            }

            let taskUpdate = TaskUpdate(
                title: title,
                body: body,
                updateType: updateType,
                costUSD: totalCost
            )
            taskUpdate.experiment = experiment
            modelContext.insert(taskUpdate)

            // Still write TASK-DRAFT.md for backward compat
            saveDraftFile()

            // Record timeline event
            let eventType: EventType = currentAction == .draftTask ? .taskDrafted : .taskUpdateDrafted
            let summary = currentAction == .draftTask
                ? "Task drafted: \(title.prefix(80))"
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

    /// Streams a generation from Claude Sonnet, updating the streaming UI. Returns cost.
    private func streamGeneration(prompt: String, workingDir: String) async throws -> Double {
        var cost: Double = 0

        for try await chunk in claudeService.streamResearch(
            prompt: prompt,
            workingDirectory: workingDir.isEmpty ? nil : workingDir,
            model: "sonnet",
            permissionMode: .readOnly,
            maxBudget: 5.0,
            maxTurns: 20
        ) {
            guard isRunning else { break }
            switch chunk {
            case .text(let text):
                rawOutput += text
                statusMessage = "Claude is writing..."
                parseStreamingOutput()
            case .sessionId:
                break
            case .result(let c, _, _):
                cost = c
                statusMessage = "Completed — $\(String(format: "%.4f", c))"
            case .error(let msg):
                error = msg
                statusMessage = "Error occurred"
            }
        }

        return cost
    }

    // MARK: - Prompt Building (Phase 2: Enhanced Context)

    private func buildDraftTaskPrompt() async -> String {
        var parts: [String] = []

        parts.append("""
        You are writing a task description for a team project tracker (Convictional). Write in direct, casual, first-person tone. Not corporate speak.

        ## Available Tools
        You have: Read, Glob, Grep, and Bash limited to: git log, git diff, git show, git merge-base, git branch, git status, wc, ls, find.
        That's it — no other commands are available. If a tool call is denied, move on and complete the task with what you have.

        Below you'll find a `git diff --stat` showing which files changed and how many lines. If you need to see the actual patch for specific files, use `git diff main...HEAD -- <path>`. Don't try to read the entire diff at once — pick the most important files.

        ## Task Format
        Structure varies by type:
        - Implementation tasks: problem context → hypothesis/approach → scope/footprint
        - Research tasks: background → hypothesis → approach → what success looks like

        Use markdown: headers, bullet points, inline links where relevant. Use <br /> for spacing between sections.
        Match length to complexity — simple tasks get 1-3 sentences, research tasks get detailed multi-section writeups.

        Cite specific files and changes when describing scope — use the diff stat and read patches for key files.

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
        let planContent = gatherPlanContent()
        if !planContent.isEmpty {
            parts.append("")
            parts.append("## Implementation Plan (PLAN.md)")
            parts.append(planContent)
        }

        // Git diff (actual code patches)
        let diffStat = await gatherGitDiffStat()
        if !diffStat.isEmpty {
            parts.append("")
            parts.append("## Changed Files (git diff --stat)")
            parts.append(diffStat)
        }

        // Git log
        let gitLog = await gatherGitLog(since: nil)
        if !gitLog.isEmpty {
            parts.append("")
            parts.append("## Git History (branch commits)")
            parts.append(gitLog)
        }

        // PR context
        let prContext = await gatherPRContext()
        if !prContext.isEmpty {
            parts.append("")
            parts.append("## Pull Request")
            parts.append(prContext)
        }

        // Artifact/notes context
        let artifactContext = gatherArtifactContents()
        if !artifactContext.isEmpty {
            parts.append("")
            parts.append("## Notes & Artifacts")
            parts.append(artifactContext)
        }

        // Recent timeline
        let timelineText = gatherTimeline(since: nil, limit: 20)
        if !timelineText.isEmpty {
            parts.append("")
            parts.append("## Recent Timeline Events")
            parts.append(timelineText)
        }

        parts.append("")
        parts.append("Now write the task. Use ## Title and ## Body headers. Match the tone and style of the examples above. Reference specific files and changes — use `git diff main...HEAD -- <path>` to read patches for the most important files.")

        return parts.joined(separator: "\n")
    }

    /// Build the extraction prompt for Step 1 (Haiku) of the two-step pipeline.
    private func buildExtractionPrompt() async -> String {
        var parts: [String] = []

        parts.append("""
        Analyze the following context from a software project and produce a structured summary. Be concise and technical.

        You have: Read, Glob, Grep, and Bash limited to: git log, git diff, git show, git merge-base, git branch, git status, wc, ls, find.
        That's it — no other commands. If a tool call is denied, move on.

        Below is a `git diff --stat` showing changed files. Use `git diff main...HEAD -- <path>` to read patches for the most important files (pick 3-5 key files, don't try to read everything at once).

        Output these sections:
        1. **Files Changed**: List each file with a 1-line description of the change
        2. **Key Technical Changes**: 3-5 bullet points on the most important changes
        3. **PR Feedback**: Summarize any review feedback or comments (or "No PR feedback available")
        4. **Apparent Status**: One sentence on the current state of the work
        """)

        // Git diff
        let diffStat = await gatherGitDiffStat()
        if !diffStat.isEmpty {
            parts.append("")
            parts.append("## Changed Files (git diff --stat)")
            parts.append(diffStat)
        }

        // Git log (since last draft)
        let lastDraftDate = lastTaskDraftDate()
        let gitLog = await gatherGitLog(since: lastDraftDate)
        if !gitLog.isEmpty {
            parts.append("")
            parts.append("## Recent Commits")
            parts.append(gitLog)
        }

        // PR context
        let prContext = await gatherPRContext()
        if !prContext.isEmpty {
            parts.append("")
            parts.append("## Pull Request")
            parts.append(prContext)
        }

        return parts.joined(separator: "\n")
    }

    /// Build the update-writing prompt for Step 2 (Sonnet) of the two-step pipeline.
    private func buildDraftUpdatePrompt(extractedSummary: String) async -> String {
        var parts: [String] = []

        parts.append("""
        You are writing a progress update comment for a task on a team project tracker (Convictional). Write in direct, casual, first-person tone. Not corporate speak.

        ## Available Tools
        You have: Read, Glob, Grep, and Bash limited to: git log, git diff, git show, git merge-base, git branch, git status, wc, ls, find.
        That's it — no other commands are available. If a tool call is denied, move on and complete the task with what you have.

        You have a pre-analyzed summary of changes below. If you need more detail on specific files, use `git diff main...HEAD -- <path>` to read patches selectively.

        ## Update Format
        This is an update comment, not a new task description. Focus on what's NEW since the last update — don't repeat what's already been said. Summarize what was done, what changed, what's next. Keep it concise but informative.

        You have the full task history below — build on the narrative. Reference specific files and changes. If there's PR feedback, address it.

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

        // Prior update history
        let history = experiment.taskUpdateHistory
        if !history.isEmpty {
            parts.append("")
            parts.append("## Task History")
            for update in history {
                let typeLabel = update.updateType == .original ? "ORIGINAL TASK" : "UPDATE"
                let dateStr = update.createdAt.formatted(date: .abbreviated, time: .shortened)
                parts.append("")
                parts.append("### [\(typeLabel)] \(dateStr) — \(update.title)")
                let truncatedBody = update.body.count > 2000 ? String(update.body.prefix(2000)) + "\n\n[...truncated]" : update.body
                parts.append(truncatedBody)
            }
        }

        // Extracted summary from Step 1
        if !extractedSummary.isEmpty {
            parts.append("")
            parts.append("## Analysis of Recent Changes")
            parts.append(extractedSummary)
        }

        // Plan content
        let planContent = gatherPlanContent()
        if !planContent.isEmpty {
            parts.append("")
            parts.append("## Implementation Plan (PLAN.md)")
            parts.append(planContent)
        }

        // Notes context
        let artifactContext = gatherArtifactContents()
        if !artifactContext.isEmpty {
            parts.append("")
            parts.append("## Notes & Artifacts")
            parts.append(artifactContext)
        }

        // Timeline since last draft
        let lastDraftDate = lastTaskDraftDate()
        let timelineText = gatherTimeline(since: lastDraftDate, limit: 20)
        if !timelineText.isEmpty {
            parts.append("")
            parts.append("## Timeline Events Since Last Update")
            parts.append(timelineText)
        }

        parts.append("")
        parts.append("Now write the update. Use ## Title and ## Body headers. Focus on NEW progress since the last update in the task history. Don't repeat what's already been covered. Reference specific files and code changes from the analysis above.")

        return parts.joined(separator: "\n")
    }

    // MARK: - Context Gathering

    /// Get the combined branch diff stat (file list + line counts). Lightweight overview
    /// that fits in any prompt — Claude can use `git diff` tools for full patches if needed.
    private func gatherGitDiffStat() async -> String {
        guard let worktree = experiment.worktreePath,
              let baseBranch = experiment.baseBranch else { return "" }

        guard let result = try? await ProcessRunner.shared.run(
            "/usr/bin/git",
            arguments: ["diff", "\(baseBranch)...HEAD", "--stat=120", "--no-color"],
            currentDirectory: worktree
        ), result.succeeded, !result.stdout.isEmpty else { return "" }

        return result.stdout
    }

    /// Get PR context: title, state, stats, reviews, comments.
    private func gatherPRContext() async -> String {
        guard let worktree = experiment.worktreePath,
              let branch = experiment.branchName else { return "" }

        // Find PR for this branch
        guard let prs = try? await appState.gitHubService.listPRs(repoPath: worktree, branch: branch),
              let pr = prs.first else { return "" }

        // Get detail
        guard let detail = try? await appState.gitHubService.getPRDetail(repoPath: worktree, prNumber: pr.number) else {
            // Fall back to list-level info
            return "**\(pr.title)** (#\(pr.number)) — \(pr.state.label)"
        }

        var lines: [String] = []
        lines.append("**\(detail.title)** (#\(detail.number)) — \(detail.state.label)")
        lines.append("+\(detail.additions) -\(detail.deletions) across \(detail.changedFiles) files")

        if !detail.reviewDecision.isEmpty {
            lines.append("Review: \(detail.reviewDecision)")
        }

        // PR body (truncated)
        if !detail.body.isEmpty {
            let truncBody = detail.body.count > 1000 ? String(detail.body.prefix(1000)) + "..." : detail.body
            lines.append("")
            lines.append("PR Description:")
            lines.append(truncBody)
        }

        // Top 5 comments
        let topComments = detail.comments.prefix(5)
        if !topComments.isEmpty {
            lines.append("")
            lines.append("Comments:")
            for comment in topComments {
                let truncComment = comment.body.count > 300 ? String(comment.body.prefix(300)) + "..." : comment.body
                lines.append("- @\(comment.author): \(truncComment)")
            }
        }

        // Top 3 reviews with inline comments
        let topReviews = detail.reviews.prefix(3)
        if !topReviews.isEmpty {
            lines.append("")
            lines.append("Reviews:")
            for review in topReviews {
                lines.append("- @\(review.author) [\(review.state.label)]")
                if !review.body.isEmpty {
                    let truncReview = review.body.count > 300 ? String(review.body.prefix(300)) + "..." : review.body
                    lines.append("  \(truncReview)")
                }
                for inlineComment in review.comments.prefix(3) {
                    lines.append("  - `\(inlineComment.path):\(inlineComment.line ?? 0)`: \(inlineComment.body.prefix(200))")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Get PLAN.md content (truncated to 3KB).
    private func gatherPlanContent() -> String {
        guard let worktree = experiment.worktreePath else { return "" }
        let planPath = (worktree as NSString).appendingPathComponent("PLAN.md")
        guard let planContent = try? String(contentsOfFile: planPath, encoding: .utf8),
              !planContent.isEmpty else { return "" }

        if planContent.count > 3000 {
            return String(planContent.prefix(3000)) + "\n\n[...truncated]"
        }
        return planContent
    }

    /// Get experiment notes (exclude archive, top 5 by updatedAt, truncated).
    private func gatherArtifactContents() -> String {
        let notes = experiment.notes
            .filter { $0.noteType != .archive }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)

        guard !notes.isEmpty else { return "" }

        var lines: [String] = []
        for note in notes {
            let truncContent = note.content.count > 500 ? String(note.content.prefix(500)) + "..." : note.content
            lines.append("**\(note.title)** (\(note.noteType.label)):")
            lines.append(truncContent)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

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

    private func lastTaskDraftDate() -> Date? {
        // Use the latest TaskUpdate createdAt, falling back to timeline events
        if let lastUpdate = experiment.taskUpdateHistory.last {
            return lastUpdate.createdAt
        }
        return experiment.timeline
            .filter { $0.eventType == .taskDrafted || $0.eventType == .taskUpdateDrafted }
            .sorted { $0.createdAt < $1.createdAt }
            .last?.createdAt
    }

    // MARK: - Output Parsing

    private func parseStreamingOutput() {
        let text = rawOutput

        // Find ## Title
        if let titleRange = text.range(of: "## Title") {
            let afterTitle = text[titleRange.upperBound...]
            let titleEnd = afterTitle.range(of: "\n## ")?.lowerBound ?? afterTitle.endIndex
            let titleContent = afterTitle[..<titleEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !titleContent.isEmpty {
                streamingTitle = titleContent
            }
        }

        // Find ## Body
        if let bodyRange = text.range(of: "## Body") {
            let afterBody = text[bodyRange.upperBound...]
            let bodyContent = afterBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bodyContent.isEmpty {
                streamingBody = bodyContent
            }
        }
    }

    // MARK: - Persistence

    /// One-time migration: import existing TASK-DRAFT.md as an .original TaskUpdate.
    private func migrateExistingDraft() {
        guard !didMigrate else { return }
        didMigrate = true

        guard experiment.taskUpdates.isEmpty,
              let worktree = experiment.worktreePath else { return }

        let path = (worktree as NSString).appendingPathComponent("TASK-DRAFT.md")
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8),
              !content.isEmpty else { return }

        // Parse title and body from the file
        var title = experiment.title
        var body = content

        if let titleRange = content.range(of: "## Title") {
            let afterTitle = content[titleRange.upperBound...]
            let titleEnd = afterTitle.range(of: "\n## ")?.lowerBound ?? afterTitle.endIndex
            let titleContent = afterTitle[..<titleEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !titleContent.isEmpty {
                title = titleContent
            }
        }

        if let bodyRange = content.range(of: "## Body") {
            let afterBody = content[bodyRange.upperBound...]
            let bodyContent = afterBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bodyContent.isEmpty {
                body = bodyContent
            }
        }

        let taskUpdate = TaskUpdate(title: title, body: body, updateType: .original)
        taskUpdate.experiment = experiment
        modelContext.insert(taskUpdate)
    }

    /// Write the latest update to TASK-DRAFT.md for backward compat with CleanupService.
    private func saveDraftFile() {
        guard let worktree = experiment.worktreePath else { return }
        let path = (worktree as NSString).appendingPathComponent("TASK-DRAFT.md")

        let title = streamingTitle.isEmpty ? experiment.title : streamingTitle
        let body = streamingBody.isEmpty ? rawOutput : streamingBody

        let content: String
        if !title.isEmpty && !body.isEmpty {
            content = "## Title\n\n\(title)\n\n## Body\n\n\(body)\n"
        } else {
            content = rawOutput
        }

        try? content.write(toFile: path, atomically: true, encoding: .utf8)
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
