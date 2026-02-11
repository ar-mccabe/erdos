import Foundation
import SwiftData
import SwiftUI

enum EventType: String, Codable, CaseIterable, Identifiable {
    case statusChange
    case noteAdded
    case artifactCreated
    case sessionStarted
    case sessionEnded
    case branchCreated
    case manual
    case autoStatusChange
    case taskDrafted
    case taskUpdateDrafted
    case worktreeCleanedUp

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
        case .autoStatusChange: "Auto Status Change"
        case .taskDrafted: "Task Drafted"
        case .taskUpdateDrafted: "Task Update Drafted"
        case .worktreeCleanedUp: "Worktree Cleaned Up"
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
        case .autoStatusChange: "sparkles"
        case .taskDrafted: "doc.text.fill"
        case .taskUpdateDrafted: "arrow.uturn.up"
        case .worktreeCleanedUp: "trash.circle"
        }
    }

    var color: Color {
        switch self {
        case .statusChange: .blue
        case .noteAdded: .purple
        case .artifactCreated: .cyan
        case .sessionStarted: .green
        case .sessionEnded: .orange
        case .branchCreated: .teal
        case .manual: .secondary
        case .autoStatusChange: .mint
        case .taskDrafted: .indigo
        case .taskUpdateDrafted: .indigo
        case .worktreeCleanedUp: .gray
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
