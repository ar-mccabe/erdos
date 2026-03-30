import Foundation
import SwiftData
import SwiftUI

enum ExperimentStatus: String, Codable, CaseIterable, Identifiable {
    case idea
    case researching
    case planned
    case implementing
    case testing
    case inReview
    case blocked
    case paused
    case merged
    case completed
    case abandoned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idea: "Idea"
        case .researching: "Researching"
        case .planned: "Planned"
        case .implementing: "Implementing"
        case .testing: "Testing"
        case .inReview: "In Review"
        case .blocked: "Blocked"
        case .paused: "Paused"
        case .merged: "Merged"
        case .completed: "Completed"
        case .abandoned: "Abandoned"
        }
    }

    var icon: String {
        switch self {
        case .idea: "lightbulb"
        case .researching: "magnifyingglass"
        case .planned: "list.bullet.clipboard"
        case .implementing: "hammer"
        case .testing: "flask"
        case .inReview: "eye"
        case .blocked: "exclamationmark.triangle"
        case .paused: "pause.circle"
        case .merged: "arrow.triangle.merge"
        case .completed: "checkmark.circle"
        case .abandoned: "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        // White → purple gradient (GitHub merge purple #8250DF)
        case .idea:           Color(red: 0.90, green: 0.88, blue: 0.93)  // near white
        case .researching:    Color(red: 0.84, green: 0.79, blue: 0.93)  // faint lavender
        case .planned:        Color(red: 0.78, green: 0.70, blue: 0.92)  // light purple
        case .implementing:   Color(red: 0.72, green: 0.61, blue: 0.92)  // medium lavender
        case .testing:        Color(red: 0.66, green: 0.52, blue: 0.91)  // medium purple
        case .inReview:       Color(red: 0.60, green: 0.43, blue: 0.91)  // deep lavender
        // Off-track
        case .blocked:        Color(red: 0.85, green: 0.38, blue: 0.38)  // coral red
        case .paused:         Color(red: 0.92, green: 0.85, blue: 0.55)  // pale yellow
        // Terminal
        case .merged:         Color(red: 0.51, green: 0.31, blue: 0.87)  // GitHub purple
        case .completed:      Color(white: 0.55)                          // gray
        case .abandoned:      Color(red: 0.90, green: 0.60, blue: 0.60)  // light red
        }
    }

    /// Sidebar grouping order: active flow → off-track → terminal
    var sortOrder: Int {
        switch self {
        // Active flow
        case .idea: 0
        case .researching: 1
        case .planned: 2
        case .implementing: 3
        case .testing: 4
        case .inReview: 5
        case .merged: 6
        // Off-track
        case .paused: 7
        case .blocked: 8
        // Terminal
        case .completed: 9
        case .abandoned: 10
        }
    }

    /// Which sidebar section this status belongs to
    var sidebarGroup: SidebarGroup {
        switch self {
        case .idea, .researching, .planned, .implementing, .testing, .inReview, .merged:
            return .active
        case .paused, .blocked:
            return .offTrack
        case .completed, .abandoned:
            return .terminal
        }
    }

    enum SidebarGroup: Int, Comparable {
        case active = 0
        case offTrack = 1
        case terminal = 2

        static func < (lhs: SidebarGroup, rhs: SidebarGroup) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

@Model
final class Experiment {
    var id: UUID
    var title: String
    var hypothesis: String
    var detail: String
    var statusRaw: String
    var repoPath: String
    var branchName: String?
    var baseBranch: String?
    var worktreePath: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var pausedContext: String?
    var envVar: String?

    @Transient var pendingInitHook: String?

    @Relationship(deleteRule: .cascade, inverse: \Note.experiment)
    var notes: [Note] = []

    @Relationship(deleteRule: .cascade, inverse: \Artifact.experiment)
    var artifacts: [Artifact] = []

    @Relationship(deleteRule: .cascade, inverse: \ClaudeSession.experiment)
    var sessions: [ClaudeSession] = []

    @Relationship(deleteRule: .cascade, inverse: \TimelineEvent.experiment)
    var timeline: [TimelineEvent] = []

    @Relationship(deleteRule: .cascade, inverse: \TaskUpdate.experiment)
    var taskUpdates: [TaskUpdate] = []

    var originalTask: TaskUpdate? {
        taskUpdates.first { $0.updateType == .original }
    }

    var taskUpdateHistory: [TaskUpdate] {
        taskUpdates.sorted { $0.createdAt < $1.createdAt }
    }

    var status: ExperimentStatus {
        get {
            if statusRaw == "active" { return .implementing }
            return ExperimentStatus(rawValue: statusRaw) ?? .idea
        }
        set {
            statusRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    init(
        title: String,
        hypothesis: String = "",
        detail: String = "",
        status: ExperimentStatus = .idea,
        repoPath: String = "",
        branchName: String? = nil,
        baseBranch: String? = nil,
        tags: [String] = []
    ) {
        self.id = UUID()
        self.title = title
        self.hypothesis = hypothesis
        self.detail = detail
        self.statusRaw = status.rawValue
        self.repoPath = repoPath
        self.branchName = branchName
        self.baseBranch = baseBranch
        self.tags = tags
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var repoName: String {
        URL(fileURLWithPath: repoPath).lastPathComponent
    }

    var slug: String {
        SlugGenerator.generate(from: title)
    }

}
