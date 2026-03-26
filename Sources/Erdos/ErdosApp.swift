import SwiftUI
import SwiftData
import AppKit

@main
struct ErdosApp: App {
    @State private var appState = AppState()
    let container: ModelContainer
    let backupService: BackupService

    init() {
        let fm = FileManager.default
        let storeDirectory = URL.applicationSupportDirectory
            .appendingPathComponent("Erdos", isDirectory: true)

        try? fm.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

        let storeURL = storeDirectory.appendingPathComponent("erdos.store")

        // One-time migration: copy default.store → dedicated Erdos/erdos.store
        if !fm.fileExists(atPath: storeURL.path) {
            let defaultStore = URL.applicationSupportDirectory
                .appendingPathComponent("default.store")

            if fm.fileExists(atPath: defaultStore.path) {
                print("[Erdos] Migrating data from default.store to Erdos/erdos.store...")
                for suffix in ["", "-wal", "-shm"] {
                    let src = URL.applicationSupportDirectory
                        .appendingPathComponent("default.store\(suffix)")
                    let dst = storeDirectory.appendingPathComponent("erdos.store\(suffix)")
                    if fm.fileExists(atPath: src.path) {
                        try? fm.copyItem(at: src, to: dst)
                    }
                }
                print("[Erdos] Migration complete. Old default.store left intact for safety.")
            }
        }

        let schema = Schema([
            Experiment.self,
            Note.self,
            Artifact.self,
            ClaudeSession.self,
            TimelineEvent.self,
            TaskUpdate.self,
        ])

        let config = ModelConfiguration(
            "ErdosStore",
            schema: schema,
            url: storeURL
        )

        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("[Erdos] Failed to create ModelContainer at \(storeURL.path): \(error)")
        }

        backupService = BackupService(storeURL: storeURL)
    }

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
                .task {
                    backupService.startPeriodicBackups()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    backupService.performBackup()
                    appState.terminateAllProcesses()
                }
        }
        .modelContainer(container)
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
