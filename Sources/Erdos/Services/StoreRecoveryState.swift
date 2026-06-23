import Foundation

/// Records that the persistent store could not be opened at launch and a fresh
/// one was substituted, so the UI can tell the user their data was preserved
/// (and where) rather than silently appearing to have lost everything.
@Observable
@MainActor
final class StoreRecoveryState {
    static let shared = StoreRecoveryState()
    private init() {}

    /// True when the store failed to open and was quarantined this launch.
    var didRecover = false
    /// Directory the unreadable store files were moved to (nil if the move failed).
    var quarantinePath: String?
    /// Most recent backup available to restore from, if any.
    var latestBackupPath: String?
    /// Underlying open failure, for display.
    var reason: String?
}
