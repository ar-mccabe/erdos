import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            if let experiment = appState.selectedExperiment {
                ExperimentDetailView(experiment: experiment)
            } else {
                ContentUnavailableView(
                    "No Experiment Selected",
                    systemImage: "flask",
                    description: Text("Select an experiment from the sidebar or create a new one.")
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        .sheet(isPresented: $state.isCreatingExperiment) {
            NewExperimentSheet()
        }
        .task {
            await appState.repoDiscovery.scan()
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                HStack(spacing: 12) {
                    if appState.activeSessionCount > 0 {
                        Label("\(appState.activeSessionCount) active", systemImage: "circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    if appState.todayCostUSD > 0 {
                        Text("$\(appState.todayCostUSD, specifier: "%.2f") today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
