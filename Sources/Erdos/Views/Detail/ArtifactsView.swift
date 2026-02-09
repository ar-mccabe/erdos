import SwiftUI
import SwiftData

struct ArtifactsView: View {
    @Bindable var experiment: Experiment
    @Environment(\.modelContext) private var modelContext
    @State private var worktreeFiles: [String] = []
    @State private var filterType: ArtifactType?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Filter", selection: $filterType) {
                    Text("All").tag(nil as ArtifactType?)
                    ForEach(ArtifactType.allCases) { type in
                        Label(type.label, systemImage: type.icon).tag(type as ArtifactType?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Spacer()

                Button("Scan Worktree") {
                    Task { await scanWorktree() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(experiment.worktreePath == nil)
            }
            .padding(8)

            Divider()

            if filteredArtifacts.isEmpty {
                ContentUnavailableView {
                    Label("No Artifacts", systemImage: "doc.on.doc")
                } description: {
                    if experiment.worktreePath == nil {
                        Text("Create a worktree to start tracking files.")
                    } else {
                        Text("Click 'Scan Worktree' to discover files, or they'll be auto-discovered as you work.")
                    }
                }
            } else {
                List {
                    ForEach(filteredArtifacts) { artifact in
                        HStack {
                            Image(systemName: artifact.artifactType.icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading) {
                                Text(artifact.fileName)
                                    .font(.body)
                                if let label = artifact.label {
                                    Text(label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(artifact.filePath)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if artifact.autoDiscovered {
                                Text("auto")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            StatusBadge(status: artifactTypeToDisplay(artifact.artifactType))
                        }
                        .contextMenu {
                            Button("Open in Finder") {
                                if let worktree = experiment.worktreePath {
                                    let fullPath = (worktree as NSString).appendingPathComponent(artifact.filePath)
                                    NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: "")
                                }
                            }
                            Button("Remove") {
                                modelContext.delete(artifact)
                            }
                        }
                    }
                }
            }
        }
        .task { await scanWorktree() }
    }

    private var filteredArtifacts: [Artifact] {
        let arts = experiment.artifacts.sorted { $0.createdAt > $1.createdAt }
        if let filter = filterType {
            return arts.filter { $0.artifactType == filter }
        }
        return arts
    }

    private func scanWorktree() async {
        guard let worktree = experiment.worktreePath else { return }

        let existingPaths = Set(experiment.artifacts.map(\.filePath))
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(atPath: worktree) else { return }

        let ignoreDirs = Set([".git", "node_modules", ".venv", "__pycache__", ".build", ".next", "dist", "build"])
        let trackExtensions = Set(["py", "swift", "ts", "tsx", "js", "jsx", "md", "json", "yaml", "yml", "toml", "rs", "go"])

        while let path = enumerator.nextObject() as? String {
            let components = path.split(separator: "/")
            if components.contains(where: { ignoreDirs.contains(String($0)) }) {
                continue
            }

            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            guard trackExtensions.contains(ext) else { continue }
            guard !existingPaths.contains(path) else { continue }

            let fullPath = (worktree as NSString).appendingPathComponent(path)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }

            let artifact = Artifact(filePath: path, autoDiscovered: true)
            artifact.experiment = experiment
            modelContext.insert(artifact)
        }
    }

    // Helper to display artifact types as status-like badges
    private func artifactTypeToDisplay(_ type: ArtifactType) -> ExperimentStatus {
        switch type {
        case .plan: .planned
        case .code: .active
        case .test: .researching
        case .config: .paused
        case .doc: .idea
        case .other: .completed
        }
    }
}
