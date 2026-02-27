import SwiftUI
import SwiftData

// MARK: - ArtifactItem

enum ArtifactItem: Identifiable, Hashable {
    case document(path: String, name: String)
    case note(Note)
    case changedFile(GitService.ChangedFile)

    var id: String {
        switch self {
        case .document(let path, _): return "doc:\(path)"
        case .note(let note): return "note:\(note.id.uuidString)"
        case .changedFile(let file): return "changed:\(file.path)"
        }
    }

    var displayName: String {
        switch self {
        case .document(_, let name): return name
        case .note(let note): return note.title
        case .changedFile(let file): return URL(fileURLWithPath: file.path).lastPathComponent
        }
    }

    var icon: String {
        switch self {
        case .document(let path, _):
            if path.lowercased().hasSuffix(".csv") { return "tablecells" }
            return "doc.text"
        case .note(let note): return note.noteType.icon
        case .changedFile(let file):
            let ext = URL(fileURLWithPath: file.path).pathExtension.lowercased()
            switch ext {
            case "swift": return "swift"
            case "py": return "chevron.left.forwardslash.chevron.right"
            case "md": return "doc.richtext"
            case "csv": return "tablecells"
            case "json", "yaml", "yml", "toml": return "gearshape"
            default: return "doc"
            }
        }
    }

    var subtitle: String {
        switch self {
        case .document(let path, _): return path
        case .note(let note): return note.noteType.label
        case .changedFile(let file):
            let dir = URL(fileURLWithPath: file.path).deletingLastPathComponent().path
            let sourceLabel: String
            switch file.source {
            case .committed: sourceLabel = "committed"
            case .uncommitted: sourceLabel = "uncommitted"
            case .both: sourceLabel = "committed + uncommitted"
            }
            return dir == "." ? sourceLabel : "\(dir) · \(sourceLabel)"
        }
    }
}

// MARK: - ArtifactsView

struct ArtifactsView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState

    @State private var changedFiles: [GitService.ChangedFile] = []
    @State private var documentPaths: [(path: String, name: String)] = []
    @State private var selectedItem: ArtifactItem?
    @State private var previewContent: String = ""
    @State private var previewError: String?
    @State private var autoRefreshTimer: Timer?
    @State private var error: String?

    var body: some View {
        Group {
            if experiment.worktreePath == nil {
                noWorktreeState
            } else if documentPaths.isEmpty && experiment.notes.isEmpty && changedFiles.isEmpty && error == nil {
                emptyState
            } else {
                HSplitView {
                    artifactListPane
                        .frame(minWidth: 180, idealWidth: 240)
                    contentPreview
                        .frame(minWidth: 300)
                }
            }
        }
        .task { await refresh() }
        .onAppear { startAutoRefresh() }
        .onDisappear { autoRefreshTimer?.invalidate() }
    }

    // MARK: - Artifact List Pane

    @ViewBuilder
    private var artifactListPane: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            artifactList
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 12) {
            if !documentPaths.isEmpty {
                Label("\(documentPaths.count) docs", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(ErdosColors.documents)
            }
            if !experiment.notes.isEmpty {
                Label("\(experiment.notes.count) notes", systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(ErdosColors.notes)
            }
            if !changedFiles.isEmpty {
                Label("\(changedFiles.count) changed", systemImage: "pencil.circle")
                    .font(.caption)
                    .foregroundStyle(ErdosColors.changedFiles)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button("Refresh") {
                Task { await refresh() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Artifact List

    @ViewBuilder
    private var artifactList: some View {
        List(selection: $selectedItem) {
            if !documentPaths.isEmpty {
                Section("Documents") {
                    ForEach(documentPaths, id: \.path) { doc in
                        let item = ArtifactItem.document(path: doc.path, name: doc.name)
                        artifactRow(item)
                            .tag(item)
                            .contextMenu {
                                openInFinderButton(relativePath: doc.path)
                                copyPathButton(relativePath: doc.path)
                            }
                    }
                }
            }

            if !experiment.notes.isEmpty {
                Section("Notes") {
                    ForEach(sortedNotes) { note in
                        let item = ArtifactItem.note(note)
                        artifactRow(item)
                            .tag(item)
                    }
                }
            }

            if !changedFiles.isEmpty {
                Section("Changed Files") {
                    ForEach(changedFilesByDirectory, id: \.directory) { group in
                        if group.directory == "." {
                            ForEach(group.files) { file in
                                let item = ArtifactItem.changedFile(file)
                                artifactRow(item)
                                    .tag(item)
                                    .contextMenu {
                                        openInFinderButton(relativePath: file.path)
                                        copyPathButton(relativePath: file.path)
                                    }
                            }
                        } else {
                            DisclosureGroup {
                                ForEach(group.files) { file in
                                    let item = ArtifactItem.changedFile(file)
                                    artifactRow(item)
                                        .tag(item)
                                        .contextMenu {
                                            openInFinderButton(relativePath: file.path)
                                            copyPathButton(relativePath: file.path)
                                        }
                                }
                            } label: {
                                Label {
                                    Text(group.directory)
                                        .font(.system(.caption, design: .monospaced))
                                } icon: {
                                    Image(systemName: "folder")
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: selectedItem) { _, newValue in
            Task { await loadContent(for: newValue) }
        }
    }

    @ViewBuilder
    private func artifactRow(_ item: ArtifactItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(.caption, design: .default))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func openInFinderButton(relativePath: String) -> some View {
        Button("Open in Finder") {
            if let worktree = experiment.worktreePath {
                let fullPath = (worktree as NSString).appendingPathComponent(relativePath)
                NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: "")
            }
        }
    }

    @ViewBuilder
    private func copyPathButton(relativePath: String) -> some View {
        Button("Copy Path") {
            if let worktree = experiment.worktreePath {
                let fullPath = (worktree as NSString).appendingPathComponent(relativePath)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullPath, forType: .string)
            }
        }
    }

    // MARK: - Content Preview

    @ViewBuilder
    private var contentPreview: some View {
        if let error = previewError {
            ContentUnavailableView {
                Label("Cannot Preview", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else if selectedItem == nil {
            ContentUnavailableView {
                Label("Select an Artifact", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Select an artifact to preview its content.")
            }
        } else if isMarkdown(selectedItem) {
            MarkdownContentView(content: previewContent)
        } else if isCSV(selectedItem) {
            CSVContentView(content: previewContent)
        } else {
            ScrollView(.vertical) {
                Text(previewContent)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
        }
    }

    private func isMarkdown(_ item: ArtifactItem?) -> Bool {
        guard let item else { return false }
        switch item {
        case .document(let path, _):
            return path.lowercased().hasSuffix(".md")
        case .note:
            return true
        case .changedFile(let file):
            return file.path.lowercased().hasSuffix(".md")
        }
    }

    private func isCSV(_ item: ArtifactItem?) -> Bool {
        guard let item else { return false }
        switch item {
        case .document(let path, _):
            return path.lowercased().hasSuffix(".csv")
        case .note:
            return false
        case .changedFile(let file):
            return file.path.lowercased().hasSuffix(".csv")
        }
    }

    // MARK: - Empty States

    @ViewBuilder
    private var noWorktreeState: some View {
        ContentUnavailableView {
            Label("No Worktree", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Create a worktree for this experiment to see artifacts.")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Artifacts", systemImage: "doc.on.doc")
        } description: {
            Text("No documents, notes, or changed files found yet.")
        }
    }

    // MARK: - Data Loading

    private var sortedNotes: [Note] {
        experiment.notes.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.createdAt > b.createdAt
        }
    }

    private var changedFilesByDirectory: [(directory: String, files: [GitService.ChangedFile])] {
        let grouped = Dictionary(grouping: changedFiles) { file in
            (file.path as NSString).deletingLastPathComponent
        }
        return grouped.sorted { $0.key < $1.key }
            .map { (directory: $0.key.isEmpty ? "." : $0.key, files: $0.value.sorted { $0.path < $1.path }) }
    }

    private func refresh() async {
        guard let worktree = experiment.worktreePath else { return }
        do {
            documentPaths = discoverDocuments(in: worktree)
            changedFiles = try await appState.gitService.getChangedFiles(
                path: worktree,
                baseBranch: experiment.baseBranch
            )
            error = nil

            // If selected item was a changed file that's no longer in the list, clear selection
            if case .changedFile(let file) = selectedItem, !changedFiles.contains(file) {
                selectedItem = nil
                previewContent = ""
                previewError = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func discoverDocuments(in worktree: String) -> [(path: String, name: String)] {
        let knownFiles = ["PLAN.md", "CLAUDE.md", "README.md", ".claude/settings.local.json"]
        let fm = FileManager.default

        var results = knownFiles.compactMap { file -> (path: String, name: String)? in
            let fullPath = (worktree as NSString).appendingPathComponent(file)
            if fm.fileExists(atPath: fullPath) {
                return (path: file, name: URL(fileURLWithPath: file).lastPathComponent)
            }
            return nil
        }

        // Auto-discover CSV files in the worktree root
        if let contents = try? fm.contentsOfDirectory(atPath: worktree) {
            let csvFiles = contents
                .filter { $0.lowercased().hasSuffix(".csv") }
                .sorted()
            for file in csvFiles {
                results.append((path: file, name: file))
            }
        }

        return results
    }

    private func loadContent(for item: ArtifactItem?) async {
        guard let item else {
            previewContent = ""
            previewError = nil
            return
        }

        // Notes use their content directly
        if case .note(let note) = item {
            previewContent = note.content
            previewError = nil
            return
        }

        // Documents and changed files: read from disk
        guard let worktree = experiment.worktreePath else {
            previewError = "No worktree available"
            return
        }

        let relativePath: String
        switch item {
        case .document(let path, _): relativePath = path
        case .changedFile(let file): relativePath = file.path
        case .note: return // handled above
        }

        let fullPath = (worktree as NSString).appendingPathComponent(relativePath)
        let fm = FileManager.default

        guard fm.fileExists(atPath: fullPath) else {
            previewContent = ""
            previewError = "File not found — it may have been deleted."
            return
        }

        // Check file size
        if let attrs = try? fm.attributesOfItem(atPath: fullPath),
           let size = attrs[.size] as? UInt64,
           size > 10_000_000 {
            previewContent = ""
            previewError = "File too large to preview (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))."
            return
        }

        do {
            previewContent = try String(contentsOfFile: fullPath, encoding: .utf8)
            previewError = nil
        } catch {
            previewContent = ""
            previewError = "Cannot read file — it may be a binary file."
        }
    }

    private func startAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                await refresh()
            }
        }
    }
}
