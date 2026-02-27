import SwiftUI

struct RecreateWorktreeSheet: View {
    @Bindable var experiment: Experiment
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var baseBranch = "main"
    @State private var branches: [GitService.BranchInfo] = []
    @State private var isLoadingBranches = true
    @State private var branchExists = false
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recreate Worktree")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Branch info
                if let branchName = experiment.branchName {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Branch").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Label(branchName, systemImage: "arrow.triangle.branch")
                                .font(.system(.body, design: .monospaced))
                            if isLoadingBranches {
                                ProgressView()
                                    .controlSize(.small)
                            } else if branchExists {
                                Label("exists", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Label("not found — will create from base", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                // Base branch picker (only relevant if branch doesn't exist)
                if !branchExists || experiment.branchName == nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Base Branch").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $baseBranch) {
                            ForEach(branches) { branch in
                                Text(branch.name).tag(branch.name)
                            }
                        }
                        .labelsHidden()
                        .disabled(isLoadingBranches)
                    }
                }

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(24)

            Spacer()

            Divider()

            // Footer
            HStack {
                Spacer()
                Button(isCreating ? "Creating..." : "Create Worktree") {
                    Task { await recreateWorktree() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating || isLoadingBranches)
            }
            .padding(16)
        }
        .frame(width: 480, height: 300)
        .task { await loadBranches() }
    }

    private func loadBranches() async {
        guard !experiment.repoPath.isEmpty else { return }
        isLoadingBranches = true
        do {
            branches = try await appState.gitService.listBranches(repoPath: experiment.repoPath)
            // Check if the experiment's branch still exists
            if let branchName = experiment.branchName {
                branchExists = branches.contains { $0.name == branchName }
            }
            // Set default base branch
            if let current = branches.first(where: \.isCurrent) {
                baseBranch = current.name
            } else if branches.contains(where: { $0.name == "main" }) {
                baseBranch = "main"
            } else if let first = branches.first {
                baseBranch = first.name
            }
        } catch {
            self.error = "Failed to load branches: \(error.localizedDescription)"
        }
        isLoadingBranches = false
    }

    private func recreateWorktree() async {
        isCreating = true
        error = nil

        let branchName = experiment.branchName ?? experiment.slug
        let effectiveBaseBranch = branchExists ? branchName : baseBranch

        do {
            let worktreePath = try await appState.gitService.createWorktree(
                repoPath: experiment.repoPath,
                branchName: branchName,
                baseBranch: effectiveBaseBranch
            )
            experiment.worktreePath = worktreePath
            experiment.branchName = branchName

            if let envName = WorktreeSetupService.applyConfig(
                repoPath: experiment.repoPath,
                worktreePath: worktreePath,
                branchName: branchName
            ) {
                experiment.envVar = envName
            }

            // Seed .erdos/notes/ with existing notes
            appState.noteSyncService.exportAllNotes(experiment: experiment)
            NoteSyncService.ensureClaudeMdNotesSection(worktreePath: worktreePath)

            let event = TimelineEvent(
                eventType: .branchCreated,
                summary: "Recreated worktree for branch '\(branchName)'"
            )
            event.experiment = experiment
            modelContext.insert(event)

            try? modelContext.save()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isCreating = false
    }
}
