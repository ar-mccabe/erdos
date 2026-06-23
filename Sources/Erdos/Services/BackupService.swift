import Foundation
import SQLite3

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
        let destURL = backupDirectory.appendingPathComponent("erdos-backup-\(timestamp).store")

        // VACUUM INTO refuses to overwrite an existing file. Timestamps are
        // per-second so a same-second collision is the only way this trips.
        guard !fm.fileExists(atPath: destURL.path) else {
            print("[Erdos Backup] Backup already exists for this second: \(destURL.lastPathComponent)")
            return false
        }

        // Produce a single, transactionally-consistent snapshot rather than
        // copying the live WAL-mode .store/-wal/-shm separately (which can
        // capture an internally inconsistent set).
        guard snapshot(from: storeURL, to: destURL) else {
            try? fm.removeItem(at: destURL)  // drop any partial file
            return false
        }

        lastBackupDate = Date()
        print("[Erdos Backup] Backup created: \(destURL.lastPathComponent)")
        pruneOldBackups()
        return true
    }

    /// Writes a consistent single-file snapshot of `src` to `dst` using SQLite's
    /// `VACUUM INTO`. The destination is self-contained (no -wal/-shm companions).
    /// Safe to run while SwiftData holds the store open: WAL mode permits a second
    /// connection, and `performBackup` is @MainActor so no SwiftData write interleaves.
    private func snapshot(from src: URL, to dst: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(src.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            print("[Erdos Backup] Failed to open store for snapshot: \(src.path)")
            return false
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "VACUUM INTO ?", -1, &stmt, nil) == SQLITE_OK else {
            print("[Erdos Backup] Failed to prepare VACUUM INTO: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        defer { sqlite3_finalize(stmt) }

        // SQLITE_TRANSIENT tells SQLite to copy the bound string.
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, dst.path, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            print("[Erdos Backup] VACUUM INTO failed: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        return true
    }

    /// Existing backup `.store` files, newest first. Sorted by the timestamp
    /// embedded in the filename (yyyy-MM-dd-HHmmss is lexicographically
    /// chronological) — NOT by file creation date, which snapshots/copies
    /// inherit identically from the source store and so cannot order backups.
    private func sortedBackupStores() -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "store" && $0.lastPathComponent.hasPrefix("erdos-backup-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func pruneOldBackups() {
        let fm = FileManager.default
        let storeFiles = sortedBackupStores()
        guard storeFiles.count > maxBackups else { return }

        let toDelete = storeFiles.suffix(from: maxBackups)
        for storeFile in toDelete {
            let base = storeFile.path
            // New backups are single files; "-wal"/"-shm" only exist for
            // legacy 3-file backups, and removeItem ignores missing paths.
            for suffix in ["", "-wal", "-shm"] {
                try? fm.removeItem(atPath: base + suffix)
            }
        }

        print("[Erdos Backup] Pruned \(toDelete.count) old backup(s)")
    }
}
