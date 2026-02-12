import SwiftUI
import SwiftData

enum TimelineItem: Identifiable {
    case event(TimelineEvent)
    case commit(GitService.CommitInfo)

    var id: String {
        switch self {
        case .event(let e): "event-\(e.id)"
        case .commit(let c): "commit-\(c.sha)"
        }
    }

    var date: Date {
        switch self {
        case .event(let e): e.createdAt
        case .commit(let c): c.date
        }
    }
}

enum TimelineFilter: String, CaseIterable {
    case all = "All"
    case eventsOnly = "Events"
    case commitsOnly = "Commits"
}

struct TimelineView: View {
    @Bindable var experiment: Experiment
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var newEventText = ""
    @State private var commits: [GitService.CommitInfo] = []
    @State private var filter: TimelineFilter = .all
    @State private var selectedCommit: GitService.CommitInfo?
    @State private var autoRefreshTimer: Timer?


    var body: some View {
        VStack(spacing: 0) {
            // Toolbar: manual event input + filter
            HStack {
                TextField("Add a note to the timeline...", text: $newEventText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addManualEvent()
                    }
                Button("Add") {
                    addManualEvent()
                }
                .disabled(newEventText.isEmpty)

                Spacer().frame(width: 12)

                Picker("Filter", selection: $filter) {
                    ForEach(TimelineFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            .padding(8)

            Divider()

            if timelineItems.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "clock",
                    description: Text("Events are recorded automatically as you work.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(timelineItems) { item in
                            switch item {
                            case .event(let event):
                                eventRow(event)
                            case .commit(let commit):
                                commitRow(commit)
                                    .onTapGesture { selectedCommit = commit }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .task { await loadCommits() }
        .onAppear { startAutoRefresh() }
        .onDisappear { autoRefreshTimer?.invalidate() }
        .popover(item: $selectedCommit) { commit in
            CommitDetailPopover(commit: commit, worktreePath: experiment.worktreePath)
        }
    }

    // MARK: - Timeline Items

    private var timelineItems: [TimelineItem] {
        var items: [TimelineItem] = []

        switch filter {
        case .all:
            items += experiment.timeline.map { .event($0) }
            items += commits.map { .commit($0) }
        case .eventsOnly:
            items += experiment.timeline.map { .event($0) }
        case .commitsOnly:
            items += commits.map { .commit($0) }
        }

        return items.sorted { $0.date > $1.date }
    }

    // MARK: - Event Row

    @ViewBuilder
    private func eventRow(_ event: TimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(event.eventType.color)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1)
            }
            .frame(width: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: event.eventType.icon)
                        .font(.caption)
                        .foregroundStyle(event.eventType.color)
                    Text(event.summary)
                        .font(.body)
                }
                if let detail = event.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(event.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)

            Spacer()
        }
    }

    // MARK: - Commit Row

    @ViewBuilder
    private func commitRow(_ commit: GitService.CommitInfo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.teal)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1)
            }
            .frame(width: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.pull")
                        .font(.caption)
                        .foregroundStyle(.teal)
                    Text(commit.shortSHA)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.teal)
                    Text(commit.message)
                        .font(.body)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text(commit.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(commit.date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 8)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Data Loading

    private func loadCommits() async {
        guard let path = experiment.worktreePath else { return }
        do {
            let fetched = try await appState.gitService.getCommitLog(
                path: path,
                baseBranch: experiment.baseBranch
            )
            commits = fetched
        } catch {
            // Silently fail — commits are supplemental
        }
    }

    private func startAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in
                await loadCommits()
            }
        }
    }

    private func addManualEvent() {
        guard !newEventText.isEmpty else { return }
        let event = TimelineEvent(eventType: .manual, summary: newEventText)
        event.experiment = experiment
        modelContext.insert(event)
        newEventText = ""
    }
}
