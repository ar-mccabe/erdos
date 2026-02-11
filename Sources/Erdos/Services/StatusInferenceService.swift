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
}

@Observable
@MainActor
final class StatusInferenceService {
    private var activityTimer: Timer?
    private let gitService = GitService()

    /// Grace period after a manual status change during which auto-inference is paused.
    private let manualOverrideGracePeriod: TimeInterval = 10 * 60 // 10 minutes

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
        // Terminal statuses are user-final — never auto-transition out of them
        if experiment.status == .completed || experiment.status == .abandoned || experiment.status == .merged {
            return
        }

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
        }
    }

    // MARK: - Staleness Timer

    private func checkForStaleness(container: ModelContainer) {
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<Experiment>(
            predicate: #Predicate {
                $0.statusRaw == "implementing" || $0.statusRaw == "testing" || $0.statusRaw == "researching"
            }
        )

        guard let liveExperiments = try? context.fetch(descriptor) else { return }

        for experiment in liveExperiments {
            if let worktree = experiment.worktreePath {
                Task {
                    if let status = try? await gitService.getStatus(path: worktree),
                       status.dirtyFiles > 0 {
                        experiment.lastActivityAt = Date()
                    }
                }
            }
        }

        try? context.save()
    }
}
