import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Experiment.updatedAt, order: .reverse) private var experiments: [Experiment]

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedExperiment) {
            if !filteredExperiments.isEmpty {
                ForEach(Array(groupedStatuses.enumerated()), id: \.element) { index, status in
                    let exps = experimentsFor(status: status)
                    if !exps.isEmpty {
                        if index > 0,
                           status.sidebarGroup != groupedStatuses[index - 1].sidebarGroup {
                            Divider()
                                .padding(.top, 8)
                        }
                        Section {
                            ForEach(exps) { experiment in
                                ExperimentRowView(experiment: experiment)
                                    .tag(experiment)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: status.icon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(status.color)
                                Text(status.label)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(status.color.opacity(0.7))
                            }
                        }
                    }
                }
            } else if !appState.searchText.isEmpty {
                ContentUnavailableView.search(text: appState.searchText)
            } else {
                ContentUnavailableView(
                    "No Experiments",
                    systemImage: "flask",
                    description: Text("Press Cmd+N to create your first experiment.")
                )
            }
        }
        .searchable(text: $state.searchText, placement: .sidebar, prompt: "Search experiments...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.isCreatingExperiment = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Experiment (⌘N)")
            }
        }
    }

    private var filteredExperiments: [Experiment] {
        if appState.searchText.isEmpty { return experiments }
        let query = appState.searchText.lowercased()
        return experiments.filter {
            $0.title.lowercased().contains(query) ||
            $0.hypothesis.lowercased().contains(query) ||
            $0.tags.contains(where: { $0.lowercased().contains(query) })
        }
    }

    private var groupedStatuses: [ExperimentStatus] {
        let statuses = Set(filteredExperiments.map(\.status))
        return statuses.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func experimentsFor(status: ExperimentStatus) -> [Experiment] {
        filteredExperiments
            .filter { $0.status == status }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
