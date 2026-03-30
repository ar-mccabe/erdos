import Foundation
import Yams

struct ErdosConfig: Codable, Sendable {
    var worktree: WorktreeConfig?
    var researchPlan: ResearchPlanConfig?

    enum CodingKeys: String, CodingKey {
        case worktree
        case researchPlan = "research_plan"
    }

    struct WorktreeConfig: Codable, Sendable {
        var copyFiles: [String]?
        var envVar: EnvVarConfig?
        var initHook: String?

        enum CodingKeys: String, CodingKey {
            case copyFiles = "copy_files"
            case envVar = "env_var"
            case initHook = "init_hook"
        }
    }

    struct EnvVarConfig: Codable, Sendable {
        var fromBranch: Bool?
        var copyBase: String?

        enum CodingKeys: String, CodingKey {
            case fromBranch = "from_branch"
            case copyBase = "copy_base"
        }
    }

    struct ResearchPlanConfig: Codable, Sendable {
        var promptPrefix: String?
        var promptSuffix: String?
        var model: String?
        var permissionMode: String?
        var allowedTools: String?
        var extraFlags: String?

        enum CodingKeys: String, CodingKey {
            case promptPrefix = "prompt_prefix"
            case promptSuffix = "prompt_suffix"
            case model
            case permissionMode = "permission_mode"
            case allowedTools = "allowed_tools"
            case extraFlags = "extra_flags"
        }
    }

    static func load(repoPath: String) -> ErdosConfig? {
        let configPath = (repoPath as NSString).appendingPathComponent(".erdos.yml")
        guard let data = FileManager.default.contents(atPath: configPath) else { return nil }
        guard let yamlString = String(data: data, encoding: .utf8) else { return nil }
        return try? YAMLDecoder().decode(ErdosConfig.self, from: yamlString)
    }

    func save(repoPath: String) {
        let configPath = (repoPath as NSString).appendingPathComponent(".erdos.yml")
        guard let yamlString = try? YAMLEncoder().encode(self) else { return }
        try? yamlString.write(toFile: configPath, atomically: true, encoding: .utf8)
    }
}
