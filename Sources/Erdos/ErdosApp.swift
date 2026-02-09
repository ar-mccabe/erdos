import SwiftUI
import SwiftData
import AppKit

@main
struct ErdosApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .onAppear {
                    // When running via `swift run` (no .app bundle), macOS doesn't
                    // make us a foreground app — so windows can't receive keyboard input.
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
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
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    appState.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 500, height: 350)
    }
}
