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

    enum DetailTab: String, CaseIterable, Identifiable {
        case plan = "Plan"
        case notes = "Notes"
        case artifacts = "Artifacts"
        case timeline = "Timeline"
        case changes = "Changes"
        case tasks = "Tasks"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .plan: "list.bullet.clipboard"
            case .notes: "note.text"
            case .artifacts: "doc.on.doc"
            case .timeline: "clock"
            case .changes: "arrow.triangle.pull"
            case .tasks: "checklist"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            experimentHeader

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
                        let old = experiment.status
                        experiment.status = newStatus
                        experiment.manualOverrideUntil = Date()
                        let event = TimelineEvent(
                            eventType: .statusChange,
                            summary: "Status changed from \(old.label) to \(newStatus.label)"
                        )
                        event.experiment = experiment
                        modelContext.insert(event)
                    }
                )) {
                    ForEach(ExperimentStatus.allCases) { s in
                        Label(s.label, systemImage: s.icon).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            HStack(spacing: 16) {
                if !experiment.repoPath.isEmpty {
                    CopyableLabel(text: experiment.repoPath, icon: "folder", display: experiment.repoName)
                }
                if let branch = experiment.branchName {
                    CopyableLabel(text: branch, icon: "arrow.triangle.branch")
                }
                if let envVar = experiment.envVar {
                    CopyableLabel(text: "ENV=\(envVar)", icon: "terminal", display: "ENV=\(envVar)")
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

            // Decide repo: generate env var and copy gitignored .env.* files from main repo
            if experiment.isDecideRepo {
                let envName = branchName
                    .replacingOccurrences(of: "-", with: "_")
                    .replacingOccurrences(of: "[^a-zA-Z0-9_]", with: "", options: .regularExpression)
                experiment.envVar = envName

                let fm = FileManager.default

                // Copy .env.development → .env.<envName> for this experiment
                let sourceEnv = (worktreePath as NSString).appendingPathComponent(".env.development")
                let targetEnv = (worktreePath as NSString).appendingPathComponent(".env.\(envName)")
                if fm.fileExists(atPath: sourceEnv) && !fm.fileExists(atPath: targetEnv) {
                    try? fm.copyItem(atPath: sourceEnv, toPath: targetEnv)
                }

                // Copy all gitignored .env.* files from main repo root and experiments/
                for subdir in ["", "experiments"] {
                    let sourceDir = subdir.isEmpty
                        ? experiment.repoPath
                        : (experiment.repoPath as NSString).appendingPathComponent(subdir)
                    let targetDir = subdir.isEmpty
                        ? worktreePath
                        : (worktreePath as NSString).appendingPathComponent(subdir)
                    if let files = try? fm.contentsOfDirectory(atPath: sourceDir) {
                        for file in files where file.hasPrefix(".env") {
                            let source = (sourceDir as NSString).appendingPathComponent(file)
                            let target = (targetDir as NSString).appendingPathComponent(file)
                            if fm.fileExists(atPath: source) && !fm.fileExists(atPath: target) {
                                try? fm.copyItem(atPath: source, toPath: target)
                            }
                        }
                    }
                }
            }

            await loadStatus()
        } catch {
            worktreeError = error.localizedDescription
        }

        isCreatingWorktree = false
    }
}

extension Notification.Name {
    static let launchClaude = Notification.Name("launchClaude")
}
