import Foundation

enum WorktreeSetupService {
    /// Applies `.erdos.yml` config to a newly created worktree.
    /// Returns the generated env var name if configured, or `nil`.
    @discardableResult
    static func applyConfig(
        repoPath: String,
        worktreePath: String,
        branchName: String
    ) -> String? {
        guard let config = ErdosConfig.load(repoPath: repoPath),
              let worktreeConfig = config.worktree else {
            return nil
        }

        let fm = FileManager.default
        var envName: String?

        // Generate env var from branch name and copy base file
        if let envVarConfig = worktreeConfig.envVar, envVarConfig.fromBranch == true {
            let generated = branchName
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: "[^a-zA-Z0-9_]", with: "", options: .regularExpression)
            envName = generated

            if let copyBase = envVarConfig.copyBase {
                let source = (worktreePath as NSString).appendingPathComponent(copyBase)
                let target = (worktreePath as NSString).appendingPathComponent(".env.\(generated)")
                if fm.fileExists(atPath: source) && !fm.fileExists(atPath: target) {
                    try? fm.copyItem(atPath: source, toPath: target)
                }
            }
        }

        // Copy gitignored files from main repo into worktree
        if let patterns = worktreeConfig.copyFiles {
            for pattern in patterns {
                copyFiles(matching: pattern, from: repoPath, to: worktreePath, fm: fm)
            }
        }

        return envName
    }

    private static func copyFiles(
        matching pattern: String,
        from repoPath: String,
        to worktreePath: String,
        fm: FileManager
    ) {
        if pattern.hasSuffix("*") {
            // Trailing wildcard: list directory and match prefix
            let prefix = String(pattern.dropLast()) // e.g. ".env" from ".env*"
            let dirComponent = (pattern as NSString).deletingLastPathComponent
            let filePrefix = (prefix as NSString).lastPathComponent

            let sourceDir = dirComponent.isEmpty
                ? repoPath
                : (repoPath as NSString).appendingPathComponent(dirComponent)
            let targetDir = dirComponent.isEmpty
                ? worktreePath
                : (worktreePath as NSString).appendingPathComponent(dirComponent)

            guard let files = try? fm.contentsOfDirectory(atPath: sourceDir) else { return }
            for file in files where file.hasPrefix(filePrefix) {
                let source = (sourceDir as NSString).appendingPathComponent(file)
                let target = (targetDir as NSString).appendingPathComponent(file)
                if fm.fileExists(atPath: source) && !fm.fileExists(atPath: target) {
                    // Ensure target subdirectory exists
                    let targetParent = (target as NSString).deletingLastPathComponent
                    try? fm.createDirectory(atPath: targetParent, withIntermediateDirectories: true)
                    try? fm.copyItem(atPath: source, toPath: target)
                }
            }
        } else {
            // Explicit file path
            let source = (repoPath as NSString).appendingPathComponent(pattern)
            let target = (worktreePath as NSString).appendingPathComponent(pattern)
            if fm.fileExists(atPath: source) && !fm.fileExists(atPath: target) {
                let targetParent = (target as NSString).deletingLastPathComponent
                try? fm.createDirectory(atPath: targetParent, withIntermediateDirectories: true)
                try? fm.copyItem(atPath: source, toPath: target)
            }
        }
    }
}
