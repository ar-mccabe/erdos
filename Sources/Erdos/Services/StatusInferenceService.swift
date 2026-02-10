import Foundation
import SwiftData

enum StatusSignal {
    case researchLaunched
    case researchCompleted
    case planDetected
    case noteAdded
    case gitActivityDetected
    case gitCommitDetected
    case branchCreated
    case activityTimeout
}

@Observable
@MainActor
final class StatusInferenceService {
    private var activityTimer: Timer?
    private let gitService = GitService()

    /// Grace period after a manual status change during which auto-inference is paused.
    private let manualOverrideGracePeriod: TimeInterval = 10 * 60 // 10 minutes

    /// How long without activity before an active experiment is considered paused.
    private let activityTimeoutInterval: TimeInterval = 2 * 60 * 60 // 2 hours

    // MARK: - Lifecycle

    func startMonitoring(container: ModelContainer) {
        guard activityTimer == nil else { return }
        activityTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForStaleness(container: container)
            }
        }
    }

    func stopMonitoring() {
        activityTimer?.invalidate()
        activityTimer = nil
    }

    // MARK: - Signal Handlers (called from views)

    func onResearchLaunched(experiment: Experiment, context: ModelContext) {
        processSignal(.researchLaunched, experiment: experiment, context: context)
    }

    func onPlanDetected(experiment: Experiment, context: ModelContext) {
        processSignal(.planDetected, experiment: experiment, context: context)
    }

    func onBranchCreated(experiment: Experiment, context: ModelContext) {
        processSignal(.branchCreated, experiment: experiment, context: context)
    }

    func onGitActivityDetected(experiment: Experiment, context: ModelContext) {
        processSignal(.gitActivityDetected, experiment: experiment, context: context)
    }

    func onGitCommitDetected(experiment: Experiment, context: ModelContext) {
        processSignal(.gitCommitDetected, experiment: experiment, context: context)
    }

    // MARK: - Core Logic

    private func processSignal(_ signal: StatusSignal, experiment: Experiment, context: ModelContext) {
        // Always update activity timestamp on any signal
        experiment.lastActivityAt = Date()

        // Check manual override (research launched from idea is strong enough to bypass)
        if let overrideUntil = experiment.manualOverrideUntil {
            let graceExpired = Date().timeIntervalSince(overrideUntil) > manualOverrideGracePeriod
            let isStrongSignal = signal == .researchLaunched && experiment.status == .idea
            if !graceExpired && !isStrongSignal {
                return
            }
        }

        guard let newStatus = inferTransition(current: experiment.status, signal: signal) else {
            return
        }

        applyTransition(experiment: experiment, newStatus: newStatus, signal: signal, context: context)
    }

    /// Pure function: given current status and signal, returns new status or nil (no transition).
    private func inferTransition(current: ExperimentStatus, signal: StatusSignal) -> ExperimentStatus? {
        switch (current, signal) {
        // Idea transitions
        case (.idea, .researchLaunched): return .researching
        case (.idea, .branchCreated): return .researching

        // Plan detection
        case (.idea, .planDetected): return .planned
        case (.researching, .planDetected): return .planned

        // Activation from planned
        case (.planned, .gitActivityDetected): return .active
        case (.planned, .gitCommitDetected): return .active

        // Staleness
        case (.active, .activityTimeout): return .paused

        // Resume from paused
        case (.paused, .gitActivityDetected): return .active
        case (.paused, .researchLaunched): return .active
        case (.paused, .gitCommitDetected): return .active

        default: return nil
        }
    }

    private func applyTransition(
        experiment: Experiment,
        newStatus: ExperimentStatus,
        signal: StatusSignal,
        context: ModelContext
    ) {
        let oldStatus = experiment.status
        experiment.status = newStatus

        let event = TimelineEvent(
            eventType: .autoStatusChange,
            summary: "Auto: \(oldStatus.label) → \(newStatus.label)",
            detail: reasonFor(signal)
        )
        event.experiment = experiment
        context.insert(event)
    }

    private func reasonFor(_ signal: StatusSignal) -> String {
        switch signal {
        case .researchLaunched: "Research session started"
        case .researchCompleted: "Research session completed"
        case .planDetected: "Implementation plan detected"
        case .noteAdded: "Note added to experiment"
        case .gitActivityDetected: "File changes detected in worktree"
        case .gitCommitDetected: "Git commit detected"
        case .branchCreated: "Worktree branch created"
        case .activityTimeout: "No activity for extended period"
        }
    }

    // MARK: - Staleness Timer

    private func checkForStaleness(container: ModelContainer) {
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<Experiment>(
            predicate: #Predicate { $0.statusRaw == "active" }
        )

        guard let activeExperiments = try? context.fetch(descriptor) else { return }

        for experiment in activeExperiments {
            // Check activity timeout
            if let lastActivity = experiment.lastActivityAt,
               Date().timeIntervalSince(lastActivity) > activityTimeoutInterval {
                processSignal(.activityTimeout, experiment: experiment, context: context)
                continue
            }

            // Check worktree for external git activity
            if let worktree = experiment.worktreePath {
                Task {
                    if let status = try? await gitService.getStatus(path: worktree),
                       status.dirtyFiles > 0 {
                        experiment.lastActivityAt = Date()
                    }
                }
            }
        }

        // Also check planned experiments for git activity (could mean they became active)
        let plannedDescriptor = FetchDescriptor<Experiment>(
            predicate: #Predicate { $0.statusRaw == "planned" }
        )

        if let plannedExperiments = try? context.fetch(plannedDescriptor) {
            for experiment in plannedExperiments {
                if let worktree = experiment.worktreePath {
                    Task {
                        if let status = try? await gitService.getStatus(path: worktree),
                           status.dirtyFiles > 0 {
                            processSignal(.gitActivityDetected, experiment: experiment, context: context)
                        }
                    }
                }
            }
        }

        try? context.save()
    }
}
