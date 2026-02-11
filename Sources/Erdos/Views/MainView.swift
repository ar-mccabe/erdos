import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Experiment.updatedAt, order: .reverse) private var experiments: [Experiment]

    /// Experiments that have been opened at least once — their views stay alive
    @State private var visitedExperimentIDs: Set<PersistentIdentifier> = []

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            ZStack {
                // Keep all visited experiment views alive (preserves terminals)
                ForEach(experiments.filter { visitedExperimentIDs.contains($0.persistentModelID) }) { experiment in
                    ExperimentDetailView(experiment: experiment)
                        .opacity(experiment.persistentModelID == appState.selectedExperiment?.persistentModelID ? 1 : 0)
                        .allowsHitTesting(experiment.persistentModelID == appState.selectedExperiment?.persistentModelID)
                }

                // Empty state when nothing selected
                if appState.selectedExperiment == nil {
                    ContentUnavailableView(
                        "No Experiment Selected",
                        systemImage: "flask",
                        description: Text("Select an experiment from the sidebar or create a new one.")
                    )
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        .onChange(of: appState.selectedExperiment) { _, newExperiment in
            if let exp = newExperiment {
                visitedExperimentIDs.insert(exp.persistentModelID)
            }
        }
        .sheet(isPresented: $state.isCreatingExperiment) {
            NewExperimentSheet()
        }
        .sheet(isPresented: $state.showSettings) {
            SettingsView()
                .padding()
        }
        .task {
            await appState.repoDiscovery.scan()
        }
        .task {
            // One-time migration: rename "active" → "implementing"
            let descriptor = FetchDescriptor<Experiment>(
                predicate: #Predicate { $0.statusRaw == "active" }
            )
            if let stale = try? modelContext.fetch(descriptor) {
                for experiment in stale {
                    experiment.statusRaw = ExperimentStatus.implementing.rawValue
                }
                try? modelContext.save()
            }
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
