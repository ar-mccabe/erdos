import Foundation
import SwiftData

enum EventType: String, Codable, CaseIterable, Identifiable {
    case statusChange
    case noteAdded
    case artifactCreated
    case sessionStarted
    case sessionEnded
    case branchCreated
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .statusChange: "Status Change"
        case .noteAdded: "Note Added"
        case .artifactCreated: "Artifact Created"
        case .sessionStarted: "Session Started"
        case .sessionEnded: "Session Ended"
        case .branchCreated: "Branch Created"
        case .manual: "Note"
        }
    }

    var icon: String {
        switch self {
        case .statusChange: "arrow.triangle.2.circlepath"
        case .noteAdded: "note.text.badge.plus"
        case .artifactCreated: "doc.badge.plus"
        case .sessionStarted: "play.fill"
        case .sessionEnded: "stop.fill"
        case .branchCreated: "arrow.triangle.branch"
        case .manual: "pencil"
        }
    }
}

@Model
final class TimelineEvent {
    var id: UUID
    var eventTypeRaw: String
    var summary: String
    var detail: String?
    var createdAt: Date
    var experiment: Experiment?

    var eventType: EventType {
        get { EventType(rawValue: eventTypeRaw) ?? .manual }
        set { eventTypeRaw = newValue.rawValue }
    }

    init(
        eventType: EventType,
        summary: String,
        detail: String? = nil
    ) {
        self.id = UUID()
        self.eventTypeRaw = eventType.rawValue
        self.summary = summary
        self.detail = detail
        self.createdAt = Date()
    }
}
