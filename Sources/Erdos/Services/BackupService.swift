import Foundation

@Observable
@MainActor
final class BackupService {
    private var timer: Timer?
    private let backupInterval: TimeInterval = 30 * 60  // 30 minutes
    private let maxBackups = 10

    private let storeURL: URL
    private let backupDirectory: URL

    private(set) var lastBackupDate: Date?

    init(storeURL: URL) {
        self.storeURL = storeURL
        self.backupDirectory = storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
    }

    func startPeriodicBackups() {
        performBackup()
        timer = Timer.scheduledTimer(withTimeInterval: backupInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performBackup()
            }
        }
    }

    func stopPeriodicBackups() {
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    func performBackup() -> Bool {
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        } catch {
            print("[Erdos Backup] Failed to create backup directory: \(error)")
            return false
        }

        guard fm.fileExists(atPath: storeURL.path) else {
            print("[Erdos Backup] No store file to back up at \(storeURL.path)")
            return false
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let baseName = "erdos-backup-\(timestamp)"

        let suffixes = ["", "-wal", "-shm"]
        var copiedAny = false

        for suffix in suffixes {
            let sourceName = storeURL.lastPathComponent + suffix
            let sourceURL = storeURL.deletingLastPathComponent().appendingPathComponent(sourceName)
            let destURL = backupDirectory.appendingPathComponent(baseName + ".store" + suffix)

            guard fm.fileExists(atPath: sourceURL.path) else { continue }

            do {
                try fm.copyItem(at: sourceURL, to: destURL)
                copiedAny = true
            } catch {
                print("[Erdos Backup] Failed to copy \(sourceName): \(error)")
            }
        }

        if copiedAny {
            lastBackupDate = Date()
            print("[Erdos Backup] Backup created: \(baseName).store")
            pruneOldBackups()
        }

        return copiedAny
    }

    private func pruneOldBackups() {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        // Find primary .store files (not -wal or -shm companions)
        let storeFiles = contents
            .filter { $0.lastPathComponent.hasSuffix(".store") }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return dateA > dateB  // newest first
            }

        guard storeFiles.count > maxBackups else { return }

        let toDelete = storeFiles.suffix(from: maxBackups)
        for storeFile in toDelete {
            let base = storeFile.path
            for suffix in ["", "-wal", "-shm"] {
                let path = base + suffix
                try? fm.removeItem(atPath: path)
            }
        }

        let pruned = toDelete.count
        print("[Erdos Backup] Pruned \(pruned) old backup(s)")
    }
}
