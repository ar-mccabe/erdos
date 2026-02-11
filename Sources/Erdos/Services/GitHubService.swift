import Foundation

enum GitHubError: Error, LocalizedError {
    case ghNotInstalled
    case notAuthenticated
    case commandFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:
            "GitHub CLI (gh) is not installed. Install with: brew install gh"
        case .notAuthenticated:
            "Not authenticated with GitHub. Run: gh auth login"
        case .commandFailed(let msg):
            "GitHub CLI error: \(msg)"
        case .parseError(let msg):
            "Failed to parse GitHub response: \(msg)"
        }
    }
}

@Observable
@MainActor
final class GitHubService {
    private let runner = ProcessRunner.shared

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let dateFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Availability

    func checkAvailability() async throws {
        // Check gh is installed
        let whichResult = try await runner.run("/usr/bin/env", arguments: ["which", "gh"])
        guard whichResult.succeeded else {
            throw GitHubError.ghNotInstalled
        }

        // Check auth status
        let ghPath = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let authResult = try await runner.run(ghPath, arguments: ["auth", "status"])
        guard authResult.succeeded else {
            throw GitHubError.notAuthenticated
        }
    }

    // MARK: - List PRs

    func listPRs(repoPath: String, branch: String?) async throws -> [GitHubPullRequest] {
        var args = [
            "pr", "list",
            "--state", "all",
            "--json", "number,title,state,author,createdAt,updatedAt,url,isDraft,headRefName,baseRefName",
            "--limit", "50"
        ]
        if let branch {
            args += ["--head", branch]
        }

        let result = try await runGH(args, in: repoPath)
        guard let data = result.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw GitHubError.parseError("Invalid JSON from gh pr list")
        }

        return json.compactMap { parsePullRequest($0) }
    }

    // MARK: - PR Detail

    func getPRDetail(repoPath: String, prNumber: Int) async throws -> GitHubPRDetail {
        let fields = [
            "number", "title", "state", "author", "body",
            "createdAt", "updatedAt", "url", "isDraft",
            "headRefName", "baseRefName",
            "additions", "deletions", "changedFiles",
            "mergeable", "reviewDecision", "labels",
            "comments", "reviews"
        ].joined(separator: ",")

        let args = [
            "pr", "view", "\(prNumber)",
            "--json", fields
        ]

        let result = try await runGH(args, in: repoPath)
        guard let data = result.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubError.parseError("Invalid JSON from gh pr view")
        }

        return try parsePRDetail(json)
    }

    // MARK: - Run GH CLI

    private func runGH(_ arguments: [String], in directory: String) async throws -> String {
        let result = try await runner.run("/usr/bin/env", arguments: ["gh"] + arguments, currentDirectory: directory)
        guard result.succeeded else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.contains("gh auth login") || stderr.contains("not logged") {
                throw GitHubError.notAuthenticated
            }
            throw GitHubError.commandFailed(stderr)
        }
        return result.stdout
    }

    // MARK: - JSON Parsing

    private func parsePullRequest(_ json: [String: Any]) -> GitHubPullRequest? {
        guard let number = json["number"] as? Int,
              let title = json["title"] as? String,
              let stateStr = json["state"] as? String else {
            return nil
        }

        let author = (json["author"] as? [String: Any])?["login"] as? String ?? "unknown"
        let createdAt = parseDate(json["createdAt"] as? String) ?? Date()
        let updatedAt = parseDate(json["updatedAt"] as? String) ?? Date()
        let url = json["url"] as? String ?? ""
        let isDraft = json["isDraft"] as? Bool ?? false
        let headRefName = json["headRefName"] as? String ?? ""
        let baseRefName = json["baseRefName"] as? String ?? ""
        let state = GitHubPullRequest.PRState(rawValue: stateStr) ?? .open

        return GitHubPullRequest(
            number: number,
            title: title,
            state: state,
            author: author,
            createdAt: createdAt,
            updatedAt: updatedAt,
            url: url,
            isDraft: isDraft,
            headRefName: headRefName,
            baseRefName: baseRefName
        )
    }

    private func parsePRDetail(_ json: [String: Any]) throws -> GitHubPRDetail {
        guard let number = json["number"] as? Int,
              let title = json["title"] as? String,
              let stateStr = json["state"] as? String else {
            throw GitHubError.parseError("Missing required fields in PR detail")
        }

        let author = (json["author"] as? [String: Any])?["login"] as? String ?? "unknown"
        let body = json["body"] as? String ?? ""
        let createdAt = parseDate(json["createdAt"] as? String) ?? Date()
        let updatedAt = parseDate(json["updatedAt"] as? String) ?? Date()
        let url = json["url"] as? String ?? ""
        let isDraft = json["isDraft"] as? Bool ?? false
        let headRefName = json["headRefName"] as? String ?? ""
        let baseRefName = json["baseRefName"] as? String ?? ""
        let additions = json["additions"] as? Int ?? 0
        let deletions = json["deletions"] as? Int ?? 0
        let changedFiles = json["changedFiles"] as? Int ?? 0
        let mergeable = json["mergeable"] as? String ?? ""
        let reviewDecision = json["reviewDecision"] as? String ?? ""
        let state = GitHubPullRequest.PRState(rawValue: stateStr) ?? .open

        // Labels
        let labelsRaw = json["labels"] as? [[String: Any]] ?? []
        let labels = labelsRaw.compactMap { $0["name"] as? String }

        // Comments
        let commentsRaw = json["comments"] as? [[String: Any]] ?? []
        let comments = commentsRaw.compactMap { parseComment($0) }

        // Reviews
        let reviewsRaw = json["reviews"] as? [[String: Any]] ?? []
        let reviews = reviewsRaw.compactMap { parseReview($0) }

        return GitHubPRDetail(
            number: number,
            title: title,
            state: state,
            author: author,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            url: url,
            isDraft: isDraft,
            headRefName: headRefName,
            baseRefName: baseRefName,
            additions: additions,
            deletions: deletions,
            changedFiles: changedFiles,
            mergeable: mergeable,
            reviewDecision: reviewDecision,
            labels: labels,
            comments: comments,
            reviews: reviews
        )
    }

    private func parseComment(_ json: [String: Any]) -> GitHubComment? {
        let author = (json["author"] as? [String: Any])?["login"] as? String ?? "unknown"
        let body = json["body"] as? String ?? ""
        let createdAt = parseDate(json["createdAt"] as? String) ?? Date()

        return GitHubComment(author: author, body: body, createdAt: createdAt)
    }

    private func parseReview(_ json: [String: Any]) -> GitHubReview? {
        let author = (json["author"] as? [String: Any])?["login"] as? String ?? "unknown"
        let stateStr = json["state"] as? String ?? "COMMENTED"
        let body = json["body"] as? String ?? ""
        let createdAt = parseDate(json["submittedAt"] as? String ?? json["createdAt"] as? String) ?? Date()
        let state = GitHubReview.ReviewState(rawValue: stateStr) ?? .commented

        let commentsRaw = json["comments"] as? [[String: Any]] ?? []
        let comments = commentsRaw.compactMap { parseReviewComment($0) }

        return GitHubReview(author: author, state: state, body: body, createdAt: createdAt, comments: comments)
    }

    private func parseReviewComment(_ json: [String: Any]) -> GitHubReviewComment? {
        let author = (json["author"] as? [String: Any])?["login"] as? String ?? "unknown"
        let body = json["body"] as? String ?? ""
        let path = json["path"] as? String ?? ""
        let line = json["line"] as? Int
        let createdAt = parseDate(json["createdAt"] as? String) ?? Date()

        return GitHubReviewComment(author: author, body: body, path: path, line: line, createdAt: createdAt)
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return Self.dateFormatter.date(from: string) ?? Self.dateFormatterNoFraction.date(from: string)
    }
}
