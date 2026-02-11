import Foundation
import Yams

struct ErdosConfig: Codable, Sendable {
    var worktree: WorktreeConfig?

    struct WorktreeConfig: Codable, Sendable {
        var copyFiles: [String]?
        var envVar: EnvVarConfig?

        enum CodingKeys: String, CodingKey {
            case copyFiles = "copy_files"
            case envVar = "env_var"
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

    static func load(repoPath: String) -> ErdosConfig? {
        let configPath = (repoPath as NSString).appendingPathComponent(".erdos.yml")
        guard let data = FileManager.default.contents(atPath: configPath) else { return nil }
        guard let yamlString = String(data: data, encoding: .utf8) else { return nil }
        return try? YAMLDecoder().decode(ErdosConfig.self, from: yamlString)
    }
}
