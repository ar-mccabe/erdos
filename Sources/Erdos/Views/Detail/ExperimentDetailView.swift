import SwiftUI
import SwiftData

struct ExperimentDetailView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: DetailTab = .research
    @State private var showTerminal = true
    @State private var terminalHeight: CGFloat = 250
    @State private var repoStatus: GitService.RepoStatus?

    enum DetailTab: String, CaseIterable, Identifiable {
        case research = "Research"
        case plan = "Plan"
        case notes = "Notes"
        case artifacts = "Artifacts"
        case timeline = "Timeline"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .research: "magnifyingglass"
            case .plan: "list.bullet.clipboard"
            case .notes: "note.text"
            case .artifacts: "doc.on.doc"
            case .timeline: "clock"
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
                        TerminalPanelView(experiment: experiment)
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
                .frame(width: 140)
            }

            HStack(spacing: 16) {
                if !experiment.repoPath.isEmpty {
                    Label(experiment.repoName, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let branch = experiment.branchName {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let status = repoStatus {
                    if status.dirtyFiles > 0 {
                        Label("\(status.dirtyFiles) changed", systemImage: "pencil.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
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
        case .research:
            ResearchView(experiment: experiment)
        case .plan:
            PlanView(experiment: experiment)
        case .notes:
            NotesListView(experiment: experiment)
        case .artifacts:
            ArtifactsView(experiment: experiment)
        case .timeline:
            TimelineView(experiment: experiment)
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
            if let sessionId = experiment.sessions.last(where: { $0.sessionId != nil })?.sessionId {
                Button("Resume Claude") {
                    // Will be implemented in terminal panel
                    NotificationCenter.default.post(
                        name: .launchClaude,
                        object: nil,
                        userInfo: ["sessionId": sessionId]
                    )
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            Button("Launch Claude") {
                NotificationCenter.default.post(name: .launchClaude, object: nil)
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
}

extension Notification.Name {
    static let launchClaude = Notification.Name("launchClaude")
}
