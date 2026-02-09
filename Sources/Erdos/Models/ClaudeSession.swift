import Foundation
import SwiftData

enum SessionStatus: String, Codable, CaseIterable, Identifiable {
    case idle
    case running
    case completed
    case errored

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .completed: "Completed"
        case .errored: "Errored"
        }
    }

    var icon: String {
        switch self {
        case .idle: "circle"
        case .running: "circle.fill"
        case .completed: "checkmark.circle.fill"
        case .errored: "exclamationmark.circle.fill"
        }
    }
}

@Model
final class ClaudeSession {
    var id: UUID
    var sessionId: String?
    var purpose: String?
    var statusRaw: String
    var model: String
    var lastPrompt: String?
    var costUSD: Double
    var inputTokens: Int
    var outputTokens: Int
    var startedAt: Date?
    var endedAt: Date?
    var experiment: Experiment?

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    init(
        purpose: String? = nil,
        model: String = "sonnet",
        sessionId: String? = nil
    ) {
        self.id = UUID()
        self.sessionId = sessionId
        self.purpose = purpose
        self.statusRaw = SessionStatus.idle.rawValue
        self.model = model
        self.costUSD = 0
        self.inputTokens = 0
        self.outputTokens = 0
    }
}
