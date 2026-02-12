import SwiftUI

struct ChangesView: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState

    @State private var files: [GitService.FileStatus] = []
    @State private var selectedFile: GitService.FileStatus?
    @State private var diffText = ""
    @State private var showStaged = false
    @State private var autoRefreshTimer: Timer?
    @State private var error: String?

    var body: some View {
        Group {
            if experiment.worktreePath == nil {
                noWorktreeState
            } else if files.isEmpty && error == nil {
                cleanTreeState
            } else {
                changesContent
            }
        }
        .task { await refresh() }
        .onAppear { startAutoRefresh() }
        .onDisappear { autoRefreshTimer?.invalidate() }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var changesContent: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if selectedFile != nil {
                HSplitView {
                    fileList
                        .frame(minWidth: 180, idealWidth: 240)
                    diffViewer
                        .frame(minWidth: 300)
                }
            } else {
                fileList
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 12) {
            let staged = files.filter(\.isStaged)
            let modified = files.filter { $0.isUnstaged && !$0.isUntracked }
            let untracked = files.filter(\.isUntracked)

            if !staged.isEmpty {
                Label("\(staged.count) staged", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if !modified.isEmpty {
                Label("\(modified.count) modified", systemImage: "pencil.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !untracked.isEmpty {
                Label("\(untracked.count) untracked", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - File List

    @ViewBuilder
    private var fileList: some View {
        List(selection: $selectedFile) {
            let staged = files.filter(\.isStaged)
            let modified = files.filter { $0.isUnstaged && !$0.isUntracked }
            let untracked = files.filter(\.isUntracked)

            if !staged.isEmpty {
                Section("Staged") {
                    ForEach(staged) { file in
                        fileRow(file)
                            .tag(file)
                    }
                }
            }

            if !modified.isEmpty {
                Section("Modified") {
                    ForEach(modified) { file in
                        fileRow(file)
                            .tag(file)
                    }
                }
            }

            if !untracked.isEmpty {
                Section("Untracked") {
                    ForEach(untracked) { file in
                        fileRow(file)
                            .tag(file)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selectedFile) { _, newValue in
            Task { await loadDiff(for: newValue) }
        }
    }

    @ViewBuilder
    private func fileRow(_ file: GitService.FileStatus) -> some View {
        HStack(spacing: 6) {
            Text(statusIcon(for: file))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(statusColor(for: file))
                .frame(width: 16)

            Text(file.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Diff Viewer

    @ViewBuilder
    private var diffViewer: some View {
        VStack(spacing: 0) {
            // Staged/unstaged picker
            HStack {
                Picker("View", selection: $showStaged) {
                    Text("Working Changes").tag(false)
                    Text("Staged Changes").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if diffText.isEmpty {
                ContentUnavailableView {
                    Label(showStaged ? "No Staged Changes" : "No Working Changes",
                          systemImage: "doc.text")
                } description: {
                    if selectedFile != nil {
                        Text("This file has no \(showStaged ? "staged" : "unstaged") changes.")
                    } else {
                        Text("Select a file to view its diff.")
                    }
                }
            } else {
                ScrollView(.vertical) {
                    Text(coloredDiff(diffText))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
            }
        }
        .onChange(of: showStaged) { _, _ in
            Task { await loadDiff(for: selectedFile) }
        }
    }

    // MARK: - Empty States

    @ViewBuilder
    private var noWorktreeState: some View {
        ContentUnavailableView {
            Label("No Worktree", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Create a worktree for this experiment to see file changes.")
        }
    }

    @ViewBuilder
    private var cleanTreeState: some View {
        ContentUnavailableView {
            Label("Clean Working Tree", systemImage: "checkmark.circle")
        } description: {
            Text("No uncommitted changes in this worktree.")
        }
    }

    // MARK: - Data Loading

    private func refresh() async {
        guard let path = experiment.worktreePath else { return }
        do {
            files = try await appState.gitService.getDetailedStatus(path: path)
            error = nil
            // If the selected file no longer exists in the list, clear selection
            if let sel = selectedFile, !files.contains(sel) {
                selectedFile = nil
                diffText = ""
            }
            // Refresh current diff too
            if selectedFile != nil {
                await loadDiff(for: selectedFile)
            } else {
                await loadFullDiff()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadDiff(for file: GitService.FileStatus?) async {
        guard let path = experiment.worktreePath else { return }
        do {
            diffText = try await appState.gitService.getDiff(
                path: path,
                staged: showStaged,
                filePath: file?.path
            )
        } catch {
            diffText = "Error loading diff: \(error.localizedDescription)"
        }
    }

    private func loadFullDiff() async {
        guard let path = experiment.worktreePath else { return }
        do {
            diffText = try await appState.gitService.getDiff(path: path, staged: showStaged)
        } catch {
            diffText = ""
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

    // MARK: - Diff Coloring

    private func coloredDiff(_ text: String) -> AttributedString {
        DiffColorizer.coloredDiff(text)
    }

    // MARK: - Helpers

    private func statusIcon(for file: GitService.FileStatus) -> String {
        if file.isUntracked { return "?" }
        return "\(file.index)\(file.worktree)"
    }

    private func statusColor(for file: GitService.FileStatus) -> Color {
        if file.isUntracked { return .secondary }
        if file.isStaged { return .green }
        return .orange
    }
}
