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

    /// Extra environment variables injected into every terminal session,
    /// one KEY=VALUE per line. Lines starting with # are ignored.
    var terminalEnvVars: String {
        didSet { UserDefaults.standard.set(terminalEnvVars, forKey: "terminalEnvVars") }
    }

    /// Default keeps Claude Code on the classic renderer: SwiftTerm doesn't
    /// forward mouse wheel events to apps, so the fullscreen/alternate-screen
    /// mode (v2.1.89+) breaks scrolling, selection, and copy.
    static let defaultTerminalEnvVars = "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1"

    /// Parses `terminalEnvVars` into a dictionary, skipping blanks, comments,
    /// and lines without a key.
    var parsedTerminalEnvVars: [String: String] {
        var result: [String: String] = [:]
        for line in terminalEnvVars.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eq)...])
            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    // MARK: - Research defaults

    /// Default --permission-mode passed to claude when launching a plan session.
    /// Per-repo .erdos.yml permissionMode overrides this.
    var defaultPermissionMode: String {
        didSet { UserDefaults.standard.set(defaultPermissionMode, forKey: "defaultPermissionMode") }
    }

    /// Default --allowed-tools list passed to claude when launching a plan session.
    /// Per-repo .erdos.yml allowedTools overrides this.
    var defaultAllowedTools: String {
        didSet { UserDefaults.standard.set(defaultAllowedTools, forKey: "defaultAllowedTools") }
    }

    /// Extra flags appended to the claude command when launching a plan session,
    /// e.g. "--login work --effort high". Per-repo .erdos.yml extraFlags overrides this.
    var defaultExtraFlags: String {
        didSet { UserDefaults.standard.set(defaultExtraFlags, forKey: "defaultExtraFlags") }
    }

    static let defaultAllowedToolsValue =
        "Read,Glob,Grep,WebSearch,WebFetch,Task," +
        "\"Bash(git log:*)\",\"Bash(git diff:*)\",\"Bash(git show:*)\"," +
        "\"Bash(git status:*)\",\"Bash(git branch:*)\",\"Bash(git -C:*)\""

    static let availableModels = [
        "claude-opus-4-8",
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
            ?? "claude-opus-4-8"

        self.terminalEnvVars = defaults.string(forKey: "terminalEnvVars")
            ?? ErdosSettings.defaultTerminalEnvVars

        self.defaultPermissionMode = defaults.string(forKey: "defaultPermissionMode")
            ?? "plan"

        self.defaultAllowedTools = defaults.string(forKey: "defaultAllowedTools")
            ?? ErdosSettings.defaultAllowedToolsValue

        self.defaultExtraFlags = defaults.string(forKey: "defaultExtraFlags")
            ?? ""
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
