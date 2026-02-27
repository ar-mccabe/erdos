import SwiftUI

struct ExperimentRowView: View {
    let experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var showDeleteConfirmation = false

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
                Task { await deleteExperiment() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the experiment, all notes, artifacts, timeline events, and task updates.\(experiment.worktreePath != nil ? " The worktree will also be removed." : "")")
        }
    }

    private func deleteExperiment() async {
        // Clean up worktree if present
        if experiment.worktreePath != nil {
            try? await appState.cleanupService.cleanupWorktree(
                for: experiment,
                context: modelContext
            )
        }

        // Clear selection if this experiment is selected
        if appState.selectedExperiment?.persistentModelID == experiment.persistentModelID {
            appState.selectedExperiment = nil
        }

        modelContext.delete(experiment)
        try? modelContext.save()
    }
}
