import Foundation

@Observable
@MainActor
final class ErdosSettings {
    static let shared = ErdosSettings()

    var worktreeBasePath: String {
        didSet { UserDefaults.standard.set(worktreeBasePath, forKey: "worktreeBasePath") }
    }

    var repoScanRoot: String {
        didSet { UserDefaults.standard.set(repoScanRoot, forKey: "repoScanRoot") }
    }

    var claudePath: String {
        didSet { UserDefaults.standard.set(claudePath, forKey: "claudePath") }
    }

    var defaultModel: String {
        didSet { UserDefaults.standard.set(defaultModel, forKey: "defaultModel") }
    }

    static let availableModels = [
        "claude-opus-4-6",
        "claude-sonnet-4-5-20250929",
        "claude-haiku-4-5-20251001",
        "sonnet",
        "opus",
        "haiku",
    ]

    private init() {
        let defaults = UserDefaults.standard

        self.worktreeBasePath = defaults.string(forKey: "worktreeBasePath")
            ?? NSHomeDirectory() + "/experiment-lab-worktrees"

        self.repoScanRoot = defaults.string(forKey: "repoScanRoot")
            ?? NSHomeDirectory() + "/GitHub"

        self.claudePath = defaults.string(forKey: "claudePath")
            ?? ErdosSettings.detectClaudePath()

        self.defaultModel = defaults.string(forKey: "defaultModel")
            ?? "claude-opus-4-6"
    }

    private static func detectClaudePath() -> String {
        let candidates = [
            NSHomeDirectory() + "/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "claude"
    }
}
