import Foundation
import SwiftData

enum StatusSignal {
    case researchLaunched
    case planDetected
    case branchCreated
}

@Observable
@MainActor
final class StatusInferenceService {

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

    // MARK: - Core Logic

    private func processSignal(_ signal: StatusSignal, experiment: Experiment, context: ModelContext) {
        // Terminal statuses are user-final — never auto-transition out of them
        if experiment.status == .completed || experiment.status == .abandoned || experiment.status == .merged {
            return
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
        case .planDetected: "Implementation plan detected"
        case .branchCreated: "Worktree branch created"
        }
    }
}
