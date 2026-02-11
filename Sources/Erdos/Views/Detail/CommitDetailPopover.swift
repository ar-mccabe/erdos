import SwiftUI

struct CommitDetailPopover: View {
    let commit: GitService.CommitInfo
    @Environment(AppState.self) private var appState

    @State private var diffText: String?
    @State private var isLoading = true

    var worktreePath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    CopyableLabel(
                        text: commit.sha,
                        icon: "number",
                        display: commit.shortSHA,
                        font: .system(.caption, design: .monospaced)
                    )
                    Spacer()
                    Text(commit.date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(commit.message)
                    .font(.body)
                    .fontWeight(.medium)

                Text(commit.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            // Diff content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let diff = diffText {
                ScrollView(.vertical) {
                    Text(DiffColorizer.coloredDiff(diff))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
            } else {
                ContentUnavailableView("No diff available", systemImage: "doc.text")
            }
        }
        .frame(width: 600, height: 500)
        .task { await loadDiff() }
    }

    private func loadDiff() async {
        guard let path = worktreePath else {
            isLoading = false
            return
        }
        do {
            diffText = try await appState.gitService.getCommitDiff(path: path, sha: commit.sha)
        } catch {
            diffText = "Error loading diff: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
