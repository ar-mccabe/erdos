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
                ForEach(groupedStatuses, id: \.self) { status in
                    let exps = experimentsFor(status: status)
                    if !exps.isEmpty {
                        Section(status.label.uppercased()) {
                            ForEach(exps) { experiment in
                                ExperimentRowView(experiment: experiment)
                                    .tag(experiment)
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
        .safeAreaInset(edge: .bottom) {
            Button {
                appState.isCreatingExperiment = true
            } label: {
                Label("New Experiment", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderless)
            .padding(8)
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
