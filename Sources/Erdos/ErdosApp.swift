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

        let schema = Schema(versionedSchema: ErdosSchemaV1.self)

        let config = ModelConfiguration(
            "ErdosStore",
            schema: schema,
            url: storeURL
        )

        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: ErdosMigrationPlan.self,
                configurations: config
            )
        } catch {
            // Never fatalError here: that would crash-loop the app and push the
            // user to delete the store. Instead preserve the unreadable store,
            // record the failure for the UI, and start fresh so the app opens.
            container = Self.recoverFromUnreadableStore(
                storeDirectory: storeDirectory,
                storeURL: storeURL,
                schema: schema,
                config: config,
                error: error
            )
        }

        backupService = BackupService(storeURL: storeURL)
    }

    /// Last-resort recovery when the store can't be opened (e.g. an incompatible
    /// schema change with no migration). Moves the unreadable store aside, records
    /// the event for the UI, and returns a fresh container so the app stays usable.
    @MainActor
    private static func recoverFromUnreadableStore(
        storeDirectory: URL,
        storeURL: URL,
        schema: Schema,
        config: ModelConfiguration,
        error: Error
    ) -> ModelContainer {
        let fm = FileManager.default
        print("[Erdos] ModelContainer open failed at \(storeURL.path): \(error)")

        // 1. Preserve the unreadable store — move aside, never delete.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let quarantineDir = storeDirectory
            .appendingPathComponent("Quarantine", isDirectory: true)
            .appendingPathComponent("erdos-\(formatter.string(from: Date()))", isDirectory: true)
        try? fm.createDirectory(at: quarantineDir, withIntermediateDirectories: true)

        var movedAny = false
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = quarantineDir.appendingPathComponent(storeURL.lastPathComponent + suffix)
            do {
                try fm.moveItem(at: src, to: dst)
                movedAny = true
            } catch {
                print("[Erdos] Failed to quarantine \(src.lastPathComponent): \(error)")
            }
        }

        // 2. Record for the UI to surface on launch.
        let recovery = StoreRecoveryState.shared
        recovery.didRecover = true
        recovery.quarantinePath = movedAny ? quarantineDir.path : nil
        recovery.latestBackupPath = BackupService.latestBackupPath(storeURL: storeURL)
        recovery.reason = error.localizedDescription

        // 3. Retry with a fresh store so the app launches.
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: ErdosMigrationPlan.self,
                configurations: config
            )
        } catch {
            fatalError("[Erdos] Unrecoverable: fresh ModelContainer also failed at \(storeURL.path): \(error)")
        }
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
                .environment(appState)
        }
        .defaultSize(width: 500, height: 700)
    }
}
