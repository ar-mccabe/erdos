import SwiftUI
import SwiftData

struct ExperimentDetailView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: DetailTab = .plan
    @State private var showTerminal = true
    @State private var terminalHeight: CGFloat = 250
    @State private var repoStatus: GitService.RepoStatus?
    @State private var isCreatingWorktree = false
    @State private var worktreeError: String?
    @State private var hasWaitingClaudeSession = false
    @State private var headCommit: GitService.CommitInfo?
    @State private var pendingTerminalStatus: ExperimentStatus?
    @State private var showCleanupConfirmation = false
    @State private var isCleaningUp = false
    @State private var cleanupError: String?
    @State private var claudeUsage: ClaudeUsage?

    enum DetailTab: String, CaseIterable, Identifiable {
        case plan = "Plan"
        case notes = "Notes"
        case artifacts = "Artifacts"
        case timeline = "Timeline"
        case changes = "Changes"
        case pullRequests = "Pull Requests"
        case tasks = "Tasks"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .plan: "list.bullet.clipboard"
            case .notes: "note.text"
            case .artifacts: "doc.on.doc"
            case .timeline: "clock"
            case .changes: "arrow.triangle.pull"
            case .pullRequests: "text.bubble"
            case .tasks: "checklist"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            experimentHeader

            if isCleaningUp {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Cleaning up worktree...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let cleanupError {
                Text(cleanupError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }

            Divider()

            // Tab bar + content
            VSplitView {
                VStack(spacing: 0) {
                    tabBar
                    Divider()
                    tabContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minHeight: 200)

                if showTerminal, experiment.worktreePath != nil {
                    VStack(spacing: 0) {
                        terminalToolbar
                        Divider()
                        TerminalPanelView(experiment: experiment, hasWaitingClaudeSession: $hasWaitingClaudeSession)
                    }
                    .frame(minHeight: 150, idealHeight: terminalHeight)
                }
            }
        }
        .task {
            await loadStatus()
        }
        .onChange(of: experiment.worktreePath) { _, _ in
            Task { await loadStatus() }
        }
        .onChange(of: hasWaitingClaudeSession) { _, waiting in
            if waiting {
                appState.experimentsWaitingForInput.insert(experiment.id)
            } else {
                appState.experimentsWaitingForInput.remove(experiment.id)
            }
        }
        .onDisappear {
            appState.experimentsWaitingForInput.remove(experiment.id)
        }
        .confirmationDialog(
            "This experiment has a worktree on disk.",
            isPresented: $showCleanupConfirmation
        ) {
            Button("Remove Worktree & Archive Files") {
                if let status = pendingTerminalStatus {
                    applyStatusChange(to: status)
                    pendingTerminalStatus = nil
                    Task { await performCleanup() }
                }
            }
            Button("Keep Worktree") {
                if let status = pendingTerminalStatus {
                    applyStatusChange(to: status)
                    pendingTerminalStatus = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingTerminalStatus = nil
            }
        } message: {
            Text("Would you like to archive gitignored files (PLAN.md, TASK-DRAFT.md, etc.) and remove the worktree?")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var experimentHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(experiment.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    if !experiment.hypothesis.isEmpty {
                        Text(experiment.hypothesis)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Status picker
                Picker("Status", selection: Binding(
                    get: { experiment.status },
                    set: { newStatus in
                        if (newStatus == .completed || newStatus == .abandoned)
                            && experiment.worktreePath != nil {
                            pendingTerminalStatus = newStatus
                            showCleanupConfirmation = true
                        } else {
                            applyStatusChange(to: newStatus)
                        }
                    }
                )) {
                    ForEach(ExperimentStatus.allCases) { s in
                        Label(s.label, systemImage: s.icon).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                .disabled(isCleaningUp)
            }

            HStack(spacing: 16) {
                if !experiment.repoPath.isEmpty {
                    CopyableLabel(text: experiment.repoPath, icon: "folder", display: experiment.repoName)
                }
                if let branch = experiment.branchName {
                    CopyableLabel(text: branch, icon: "arrow.triangle.branch")
                }
                if let commit = headCommit {
                    CopyableLabel(
                        text: commit.sha,
                        icon: "number",
                        display: "\(commit.shortSHA) \(String(commit.message.prefix(40)))"
                    )
                }
                if let envVar = experiment.envVar {
                    CopyableLabel(text: "ENV=\(envVar)", icon: "terminal", display: "ENV=\(envVar)")
                }
                if let usage = claudeUsage, usage.inputTokens > 0 {
                    CopyableLabel(
                        text: "Input: \(usage.inputTokens.formatted()) / Output: \(usage.outputTokens.formatted())",
                        icon: "number.square",
                        display: "\(TokenFormatter.compact(usage.inputTokens)) / \(TokenFormatter.compact(usage.outputTokens))"
                    )
                    CopyableLabel(
                        text: String(format: "$%.2f", usage.costUSD),
                        icon: "dollarsign.circle",
                        display: String(format: "$%.2f", usage.costUSD)
                    )
                }
                if let status = repoStatus {
                    if status.dirtyFiles > 0 {
                        Label("\(status.dirtyFiles) changed", systemImage: "pencil.circle")
                            .font(.caption)
                            .foregroundStyle(ErdosColors.dirtyIndicator)
                    }
                }
                if experiment.worktreePath != nil {
                    Button {
                        showTerminal.toggle()
                    } label: {
                        Label(showTerminal ? "Hide Terminal" : "Show Terminal",
                              systemImage: "terminal")
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                } else if !experiment.repoPath.isEmpty {
                    Button {
                        Task { await createWorktree() }
                    } label: {
                        Label(isCreatingWorktree ? "Creating..." : "Create Worktree",
                              systemImage: "plus.rectangle.on.folder")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCreatingWorktree)

                    if let worktreeError {
                        Text(worktreeError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .help(worktreeError)
                    }
                }

                if !experiment.tags.isEmpty {
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(experiment.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding()
    }

    // MARK: - Tabs

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .plan:
            PlanView(experiment: experiment)
        case .notes:
            NotesListView(experiment: experiment)
        case .artifacts:
            ArtifactsView(experiment: experiment)
        case .timeline:
            TimelineView(experiment: experiment)
        case .changes:
            ChangesView(experiment: experiment)
        case .pullRequests:
            PullRequestsView(experiment: experiment)
        case .tasks:
            TaskDraftView(experiment: experiment)
        }
    }

    // MARK: - Terminal Toolbar

    @ViewBuilder
    private var terminalToolbar: some View {
        HStack {
            Label("Terminal", systemImage: "terminal")
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Button("Launch Claude") {
                NotificationCenter.default.post(
                    name: .launchClaude,
                    object: nil,
                    userInfo: ["experimentId": experiment.id.uuidString]
                )
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func loadStatus() async {
        guard let path = experiment.worktreePath ?? (experiment.repoPath.isEmpty ? nil : experiment.repoPath) else { return }
        repoStatus = try? await appState.gitService.getStatus(path: path)
        headCommit = try? await appState.gitService.getHeadCommit(path: path)
        claudeUsage = await ClaudeUsageService.loadUsage(forPath: path)
    }

    private func createWorktree() async {
        guard !experiment.repoPath.isEmpty else { return }
        isCreatingWorktree = true
        worktreeError = nil

        let branchName = experiment.branchName ?? experiment.slug
        let baseBranch = experiment.baseBranch ?? "main"

        do {
            let worktreePath = try await appState.gitService.createWorktree(
                repoPath: experiment.repoPath,
                branchName: branchName,
                baseBranch: baseBranch
            )
            experiment.worktreePath = worktreePath
            experiment.branchName = branchName
            experiment.baseBranch = baseBranch

            let event = TimelineEvent(
                eventType: .branchCreated,
                summary: "Created worktree with branch '\(branchName)'"
            )
            event.experiment = experiment
            modelContext.insert(event)

            appState.statusInference.onBranchCreated(experiment: experiment, context: modelContext)

            if let envName = WorktreeSetupService.applyConfig(
                repoPath: experiment.repoPath,
                worktreePath: worktreePath,
                branchName: branchName
            ) {
                experiment.envVar = envName
            }

            // Seed .erdos/notes/ with existing notes
            appState.noteSyncService.exportAllNotes(experiment: experiment)

            // Generate CLAUDE.md notes section so Claude Code knows about notes
            NoteSyncService.ensureClaudeMdNotesSection(worktreePath: worktreePath)

            await loadStatus()
        } catch {
            worktreeError = error.localizedDescription
        }

        isCreatingWorktree = false
    }

    private func applyStatusChange(to newStatus: ExperimentStatus) {
        let old = experiment.status
        experiment.status = newStatus
        let event = TimelineEvent(
            eventType: .statusChange,
            summary: "Status changed from \(old.label) to \(newStatus.label)"
        )
        event.experiment = experiment
        modelContext.insert(event)
    }

    private func performCleanup() async {
        isCleaningUp = true
        cleanupError = nil
        do {
            try await appState.cleanupService.cleanupWorktree(
                for: experiment,
                context: modelContext
            )
        } catch {
            cleanupError = error.localizedDescription
        }
        isCleaningUp = false
    }
}

extension Notification.Name {
    static let launchClaude = Notification.Name("launchClaude")
}
