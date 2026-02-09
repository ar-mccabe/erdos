import Foundation

@Observable
@MainActor
final class RepoDiscoveryService {
    var repos: [RepoInfo] = []
    var isScanning = false

    struct RepoInfo: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let path: String

        init(path: String) {
            self.path = path
            self.name = URL(fileURLWithPath: path).lastPathComponent
            self.id = path
        }
    }

    private let scanRoot: String

    init(scanRoot: String = NSHomeDirectory() + "/GitHub") {
        self.scanRoot = scanRoot
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }

        let root = scanRoot
        let found = await Task.detached { () -> [RepoInfo] in
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(atPath: root) else { return [] }

            var results: [RepoInfo] = []
            for item in contents.sorted() {
                let fullPath = (root as NSString).appendingPathComponent(item)
                let gitDir = (fullPath as NSString).appendingPathComponent(".git")

                var isDir: ObjCBool = false
                // .git can be a directory (regular repo) or a file (worktree)
                if fm.fileExists(atPath: gitDir, isDirectory: &isDir) {
                    if isDir.boolValue {
                        results.append(RepoInfo(path: fullPath))
                    }
                    // Skip worktrees (.git is a file) - we only want main repos
                }
            }
            return results
        }.value

        repos = found
    }
}
