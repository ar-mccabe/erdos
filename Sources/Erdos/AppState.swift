import Foundation
import SwiftData

@Observable
@MainActor
final class AppState {
    var selectedExperiment: Experiment?
    var isCreatingExperiment = false
    var searchText = ""
    var showSettings = false

    // Services
    let repoDiscovery = RepoDiscoveryService()
    let gitService = GitService()
    let statusInference = StatusInferenceService()

    // Notification dots — experiments with a Claude session waiting for input
    var experimentsWaitingForInput: Set<UUID> = []

    // Status bar
    var activeSessionCount = 0
    var todayCostUSD: Double = 0

    func updateStats(context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<ClaudeSession>()
        if let sessions = try? context.fetch(descriptor) {
            activeSessionCount = sessions.filter { $0.status == .running }.count
            todayCostUSD = sessions
                .filter { $0.startedAt != nil && $0.startedAt! >= today }
                .reduce(0) { $0 + $1.costUSD }
        }
    }
}
