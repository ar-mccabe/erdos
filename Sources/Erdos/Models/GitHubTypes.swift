import Foundation

// MARK: - PR List Item (from `gh pr list`)

struct GitHubPullRequest: Identifiable, Hashable, Sendable {
    let number: Int
    let title: String
    let state: PRState
    let author: String
    let createdAt: Date
    let updatedAt: Date
    let url: String
    let isDraft: Bool
    let headRefName: String
    let baseRefName: String

    var id: Int { number }

    enum PRState: String, Sendable {
        case open = "OPEN"
        case closed = "CLOSED"
        case merged = "MERGED"

        var label: String {
            switch self {
            case .open: "Open"
            case .closed: "Closed"
            case .merged: "Merged"
            }
        }

        var icon: String {
            switch self {
            case .open: "arrow.triangle.pull"
            case .closed: "xmark.circle"
            case .merged: "arrow.triangle.merge"
            }
        }

        var color: String {
            switch self {
            case .open: "green"
            case .closed: "red"
            case .merged: "purple"
            }
        }
    }
}

// MARK: - PR Detail (from `gh pr view`)

struct GitHubPRDetail: Sendable {
    let number: Int
    let title: String
    let state: GitHubPullRequest.PRState
    let author: String
    let body: String
    let createdAt: Date
    let updatedAt: Date
    let url: String
    let isDraft: Bool
    let headRefName: String
    let baseRefName: String
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let mergeable: String
    let reviewDecision: String
    let labels: [String]
    let comments: [GitHubComment]
    let reviews: [GitHubReview]
}

// MARK: - Issue Comment

struct GitHubComment: Identifiable, Sendable {
    let id: String
    let author: String
    let body: String
    let createdAt: Date

    init(author: String, body: String, createdAt: Date) {
        self.id = UUID().uuidString
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }
}

// MARK: - Review

struct GitHubReview: Identifiable, Sendable {
    let id: String
    let author: String
    let state: ReviewState
    let body: String
    let createdAt: Date
    let comments: [GitHubReviewComment]

    init(author: String, state: ReviewState, body: String, createdAt: Date, comments: [GitHubReviewComment] = []) {
        self.id = UUID().uuidString
        self.author = author
        self.state = state
        self.body = body
        self.createdAt = createdAt
        self.comments = comments
    }

    enum ReviewState: String, Sendable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case commented = "COMMENTED"
        case dismissed = "DISMISSED"
        case pending = "PENDING"

        var label: String {
            switch self {
            case .approved: "Approved"
            case .changesRequested: "Changes Requested"
            case .commented: "Commented"
            case .dismissed: "Dismissed"
            case .pending: "Pending"
            }
        }

        var icon: String {
            switch self {
            case .approved: "checkmark.circle.fill"
            case .changesRequested: "exclamationmark.circle.fill"
            case .commented: "text.bubble.fill"
            case .dismissed: "minus.circle.fill"
            case .pending: "clock.fill"
            }
        }
    }
}

// MARK: - Inline Review Comment

struct GitHubReviewComment: Identifiable, Sendable {
    let id: String
    let author: String
    let body: String
    let path: String
    let line: Int?
    let createdAt: Date

    init(author: String, body: String, path: String, line: Int?, createdAt: Date) {
        self.id = UUID().uuidString
        self.author = author
        self.body = body
        self.path = path
        self.line = line
        self.createdAt = createdAt
    }
}

// MARK: - Timeline Item (unified for chronological display)

enum PRTimelineItem: Identifiable, Sendable {
    case comment(GitHubComment)
    case review(GitHubReview)

    var id: String {
        switch self {
        case .comment(let c): "comment-\(c.id)"
        case .review(let r): "review-\(r.id)"
        }
    }

    var date: Date {
        switch self {
        case .comment(let c): c.createdAt
        case .review(let r): r.createdAt
        }
    }
}
