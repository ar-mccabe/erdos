import Foundation

@Observable
@MainActor
final class GitService {
    static var worktreeBase: String { ErdosSettings.shared.worktreeBasePath }

    private let runner = ProcessRunner.shared

    struct BranchInfo: Identifiable, Hashable, Sendable {
        let name: String
        let isCurrent: Bool
        var id: String { name }
    }

    struct WorktreeInfo: Sendable {
        let path: String
        let branch: String?
        let head: String?
        let isBare: Bool
    }

    struct RepoStatus: Sendable {
        let branch: String
        let dirtyFiles: Int
        let ahead: Int
        let behind: Int
    }

    struct FileStatus: Sendable, Identifiable, Hashable {
        let index: Character    // X — index/staging area status
        let worktree: Character // Y — working tree status
        let path: String

        var id: String { path }

        var isStaged: Bool {
            index != " " && index != "?"
        }

        var isUnstaged: Bool {
            worktree != " " && worktree != "?"
        }

        var isUntracked: Bool {
            index == "?" && worktree == "?"
        }

        var statusLabel: String {
            switch (index, worktree) {
            case ("?", "?"): return "Untracked"
            case ("A", _): return "Added"
            case ("D", _): return "Deleted"
            case ("R", _): return "Renamed"
            case ("M", " "): return "Staged"
            case (" ", "M"): return "Modified"
            case ("M", "M"): return "Staged + Modified"
            default: return "\(index)\(worktree)"
            }
        }
    }

    // MARK: - Branches

    func listBranches(repoPath: String) async throws -> [BranchInfo] {
        let result = try await runner.git("branch", "--list", "--no-color", in: repoPath)
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }

        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let isCurrent = trimmed.hasPrefix("* ")
                let name = isCurrent ? String(trimmed.dropFirst(2)) : trimmed
                return BranchInfo(name: name, isCurrent: isCurrent)
            }
    }

    // MARK: - Worktrees

    func createWorktree(repoPath: String, branchName: String, baseBranch: String) async throws -> String {
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        let slug = SlugGenerator.generate(from: branchName)
        let worktreePath = "\(Self.worktreeBase)/\(repoName)--\(slug)"

        // Ensure base directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.worktreeBase) {
            try fm.createDirectory(atPath: Self.worktreeBase, withIntermediateDirectories: true)
        }

        // Clean up stale worktree directory from a previous failed attempt
        if fm.fileExists(atPath: worktreePath) {
            try fm.removeItem(atPath: worktreePath)
            // Also prune git's worktree list
            _ = try? await runner.git("worktree", "prune", in: repoPath)
        }

        // Check if branch already exists
        let branchCheck = try await runner.git("rev-parse", "--verify", branchName, in: repoPath)
        let branchExists = branchCheck.succeeded

        let result: ProcessResult
        if branchExists {
            // Use existing branch
            result = try await runner.git(
                "worktree", "add", worktreePath, branchName,
                in: repoPath
            )
        } else {
            // Create new branch from base
            result = try await runner.git(
                "worktree", "add", "-b", branchName, worktreePath, baseBranch,
                in: repoPath
            )
        }

        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }

        return worktreePath
    }

    func removeWorktree(repoPath: String, worktreePath: String) async throws {
        let result = try await runner.git("worktree", "remove", worktreePath, in: repoPath)
        if !result.succeeded {
            // Try force removal
            let forceResult = try await runner.git("worktree", "remove", "--force", worktreePath, in: repoPath)
            guard forceResult.succeeded else { throw GitError.commandFailed(forceResult.stderr) }
        }
        _ = try await runner.git("worktree", "prune", in: repoPath)
    }

    func listWorktrees(repoPath: String) async throws -> [WorktreeInfo] {
        let result = try await runner.git("worktree", "list", "--porcelain", in: repoPath)
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }

        var worktrees: [WorktreeInfo] = []
        var currentPath: String?
        var currentBranch: String?
        var currentHead: String?
        var isBare = false

        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let str = String(line)
            if str.hasPrefix("worktree ") {
                // Save previous
                if let path = currentPath {
                    worktrees.append(WorktreeInfo(path: path, branch: currentBranch, head: currentHead, isBare: isBare))
                }
                currentPath = String(str.dropFirst("worktree ".count))
                currentBranch = nil
                currentHead = nil
                isBare = false
            } else if str.hasPrefix("HEAD ") {
                currentHead = String(str.dropFirst("HEAD ".count))
            } else if str.hasPrefix("branch ") {
                let ref = String(str.dropFirst("branch ".count))
                currentBranch = ref.replacingOccurrences(of: "refs/heads/", with: "")
            } else if str == "bare" {
                isBare = true
            }
        }
        // Don't forget the last one
        if let path = currentPath {
            worktrees.append(WorktreeInfo(path: path, branch: currentBranch, head: currentHead, isBare: isBare))
        }

        return worktrees
    }

    // MARK: - Status

    func getStatus(path: String) async throws -> RepoStatus {
        let branchResult = try await runner.git("rev-parse", "--abbrev-ref", "HEAD", in: path)
        let branch = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        let statusResult = try await runner.git("status", "--porcelain", in: path)
        let dirtyFiles = statusResult.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .count

        // Try to get ahead/behind
        var ahead = 0
        var behind = 0
        let abResult = try await runner.git("rev-list", "--left-right", "--count", "@{upstream}...HEAD", in: path)
        if abResult.succeeded {
            let parts = abResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
            if parts.count == 2 {
                behind = Int(parts[0]) ?? 0
                ahead = Int(parts[1]) ?? 0
            }
        }

        return RepoStatus(branch: branch, dirtyFiles: dirtyFiles, ahead: ahead, behind: behind)
    }

    // MARK: - Detailed Status & Diff

    func getDetailedStatus(path: String) async throws -> [FileStatus] {
        let result = try await runner.git("status", "--porcelain=v1", in: path)
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }

        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> FileStatus? in
                // Porcelain v1: XY <space> filename  (minimum 4 chars: "XY F")
                guard line.count >= 4 else { return nil }
                let index = line[line.startIndex]
                let worktree = line[line.index(after: line.startIndex)]
                let filePath = String(line.dropFirst(3))
                return FileStatus(index: index, worktree: worktree, path: filePath)
            }
    }

    func getDiff(path: String, staged: Bool, filePath: String? = nil) async throws -> String {
        var args = ["diff", "--patch-with-stat", "--no-color"]
        if staged { args.append("--cached") }
        if let filePath { args.append(contentsOf: ["--", filePath]) }

        let result = try await runner.run("/usr/bin/git", arguments: args, currentDirectory: path)
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
        return result.stdout
    }

    enum GitError: Error, LocalizedError {
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let msg): "Git error: \(msg)"
            }
        }
    }
}
