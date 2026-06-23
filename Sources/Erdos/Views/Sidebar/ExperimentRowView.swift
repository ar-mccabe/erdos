import SwiftUI

struct ExperimentRowView: View {
    let experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var showDeleteConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var dirtySummary: [String] = []
    @State private var cleanupError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(experiment.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if appState.experimentsWaitingForInput.contains(experiment.id) {
                    Circle()
                        .fill(ErdosColors.attentionDot)
                        .frame(width: 8, height: 8)
                }
                Spacer()
                if !experiment.repoPath.isEmpty {
                    RepoBadge(name: experiment.repoName)
                }
            }
            if !experiment.hypothesis.isEmpty {
                Text(experiment.hypothesis)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .opacity(experiment.status == .completed || experiment.status == .abandoned ? 0.5 : 1.0)
        .padding(.vertical, 2)
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Experiment", systemImage: "trash")
            }
        }
        .alert("Delete \"\(experiment.title)\"?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await requestDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the experiment, all notes, artifacts, timeline events, and task updates.\(experiment.worktreePath != nil ? " The worktree will also be removed." : "")")
        }
        .confirmationDialog(
            "This worktree has \(dirtySummary.count) uncommitted change(s).",
            isPresented: $showDiscardConfirmation
        ) {
            Button("Discard Changes & Delete", role: .destructive) {
                Task { await performDelete(force: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These changes in the worktree will be permanently lost:\n\n\(dirtyPreview)\n\nDelete anyway?")
        }
        .alert("Couldn't remove worktree", isPresented: Binding(
            get: { cleanupError != nil },
            set: { if !$0 { cleanupError = nil } }
        )) {
            Button("OK", role: .cancel) { cleanupError = nil }
        } message: {
            Text((cleanupError ?? "") + "\n\nThe experiment was NOT deleted, so its worktree isn't orphaned.")
        }
    }

    private var dirtyPreview: String {
        let shown = dirtySummary.prefix(15).joined(separator: "\n")
        return dirtySummary.count > 15 ? shown + "\n…and \(dirtySummary.count - 15) more" : shown
    }

    /// Check for uncommitted work before deleting. If the worktree is dirty,
    /// route through an explicit discard confirmation; otherwise delete directly.
    private func requestDelete() async {
        if experiment.worktreePath != nil {
            let dirty = await appState.cleanupService.uncommittedSummary(for: experiment)
            if !dirty.isEmpty {
                dirtySummary = dirty
                showDiscardConfirmation = true
                return
            }
        }
        await performDelete(force: false)
    }

    private func performDelete(force: Bool) async {
        // Remove the worktree FIRST. If it fails, keep the experiment record so
        // its worktreePath pointer isn't orphaned — surface the error instead.
        if experiment.worktreePath != nil {
            do {
                try await appState.cleanupService.cleanupWorktree(
                    for: experiment,
                    context: modelContext,
                    force: force
                )
            } catch {
                cleanupError = error.localizedDescription
                return
            }
        }

        // Clear selection if this experiment is selected
        if appState.selection == .experiment(experiment.persistentModelID) {
            appState.selection = nil
        }

        modelContext.delete(experiment)
        try? modelContext.save()
    }
}
