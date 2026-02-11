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
        case .idea: .purple
        case .researching: .blue
        case .planned: .cyan
        case .implementing: .green
        case .testing: .teal
        case .inReview: .indigo
        case .blocked: .red
        case .paused: .orange
        case .merged: .mint
        case .completed: .gray
        case .abandoned: .secondary
        }
    }

    /// Sidebar grouping order
    var sortOrder: Int {
        switch self {
        case .idea: 0
        case .researching: 1
        case .planned: 2
        case .paused: 3
        case .blocked: 4
        case .implementing: 5
        case .testing: 6
        case .inReview: 7
        case .merged: 8
        case .completed: 9
        case .abandoned: 10
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

    @Relationship(deleteRule: .cascade, inverse: \Note.experiment)
    var notes: [Note] = []

    @Relationship(deleteRule: .cascade, inverse: \Artifact.experiment)
    var artifacts: [Artifact] = []

    @Relationship(deleteRule: .cascade, inverse: \ClaudeSession.experiment)
    var sessions: [ClaudeSession] = []

    @Relationship(deleteRule: .cascade, inverse: \TimelineEvent.experiment)
    var timeline: [TimelineEvent] = []

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
