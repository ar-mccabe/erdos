import SwiftUI
import SwiftData

@main
struct ErdosApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
        }
        .modelContainer(for: [
            Experiment.self,
            Note.self,
            Artifact.self,
            ClaudeSession.self,
            TimelineEvent.self,
        ])
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Experiment") {
                    appState.isCreatingExperiment = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
