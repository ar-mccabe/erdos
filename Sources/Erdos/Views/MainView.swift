import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Experiment.updatedAt, order: .reverse) private var experiments: [Experiment]

    /// Experiments that have been opened at least once — their views stay alive
    @State private var visitedExperimentIDs: Set<PersistentIdentifier> = []
    @State private var hasVisitedAdHocTerminals = false

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            ZStack {
                // Ad-hoc terminals — stays alive once visited
                if hasVisitedAdHocTerminals {
                    AdHocTerminalView()
                        .opacity(appState.selection == .adHocTerminals ? 1 : 0)
                        .allowsHitTesting(appState.selection == .adHocTerminals)
                }

                // Keep all visited experiment views alive (preserves terminals)
                ForEach(experiments.filter { visitedExperimentIDs.contains($0.persistentModelID) }) { experiment in
                    ExperimentDetailView(experiment: experiment)
                        .opacity(appState.selectedExperimentID == experiment.persistentModelID ? 1 : 0)
                        .allowsHitTesting(appState.selectedExperimentID == experiment.persistentModelID)
                }

                // Empty state when nothing selected
                if appState.selection == nil {
                    ContentUnavailableView(
                        "No Experiment Selected",
                        systemImage: "flask",
                        description: Text("Select an experiment from the sidebar or create a new one.")
                    )
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        .onChange(of: appState.selection) { _, newSelection in
            switch newSelection {
            case .adHocTerminals:
                hasVisitedAdHocTerminals = true
            case .experiment(let id):
                visitedExperimentIDs.insert(id)
            case nil:
                break
            }
        }
        .onChange(of: experiments.count) { _, _ in
            // Prune stale IDs for deleted experiments
            let currentIDs = Set(experiments.map(\.persistentModelID))
            visitedExperimentIDs.formIntersection(currentIDs)
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
