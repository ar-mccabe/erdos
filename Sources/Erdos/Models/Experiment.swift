import Foundation
import SwiftData

enum ExperimentStatus: String, Codable, CaseIterable, Identifiable {
    case idea
    case researching
    case planned
    case active
    case paused
    case completed
    case abandoned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idea: "Idea"
        case .researching: "Researching"
        case .planned: "Planned"
        case .active: "Active"
        case .paused: "Paused"
        case .completed: "Completed"
        case .abandoned: "Abandoned"
        }
    }

    var icon: String {
        switch self {
        case .idea: "lightbulb"
        case .researching: "magnifyingglass"
        case .planned: "list.bullet.clipboard"
        case .active: "play.circle"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle"
        case .abandoned: "xmark.circle"
        }
    }

    var isLive: Bool {
        switch self {
        case .active, .researching: true
        default: false
        }
    }

    /// Sidebar grouping order
    var sortOrder: Int {
        switch self {
        case .active: 0
        case .researching: 1
        case .planned: 2
        case .idea: 3
        case .paused: 4
        case .completed: 5
        case .abandoned: 6
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
    var lastActivityAt: Date?
    var manualOverrideUntil: Date?

    @Relationship(deleteRule: .cascade, inverse: \Note.experiment)
    var notes: [Note] = []

    @Relationship(deleteRule: .cascade, inverse: \Artifact.experiment)
    var artifacts: [Artifact] = []

    @Relationship(deleteRule: .cascade, inverse: \ClaudeSession.experiment)
    var sessions: [ClaudeSession] = []

    @Relationship(deleteRule: .cascade, inverse: \TimelineEvent.experiment)
    var timeline: [TimelineEvent] = []

    var status: ExperimentStatus {
        get { ExperimentStatus(rawValue: statusRaw) ?? .idea }
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
