import Foundation
import SwiftData

@Observable
@MainActor
final class CleanupService {
    private let gitService = GitService()
    private let fileManager = FileManager.default

    /// Archives gitignored files as Notes, removes the worktree, and logs a timeline event.
    func cleanupWorktree(for experiment: Experiment, context: ModelContext) async throws {
        guard let worktreePath = experiment.worktreePath else { return }

        // Archive phase — read gitignored files and save as archive notes
        let archivedFiles = archiveFiles(from: worktreePath, for: experiment, context: context)

        // Removal phase — remove the worktree via git
        try await gitService.removeWorktree(
            repoPath: experiment.repoPath,
            worktreePath: worktreePath
        )

        experiment.worktreePath = nil

        // Log timeline event
        let fileSummary = archivedFiles.isEmpty
            ? "no files archived"
            : archivedFiles.joined(separator: ", ")
        let event = TimelineEvent(
            eventType: .worktreeCleanedUp,
            summary: "Worktree removed — archived \(archivedFiles.count) file(s): \(fileSummary)"
        )
        event.experiment = experiment
        context.insert(event)
    }

    // MARK: - Private

    private func archiveFiles(
        from worktreePath: String,
        for experiment: Experiment,
        context: ModelContext
    ) -> [String] {
        var archived: [String] = []

        let fixedFiles = ["PLAN.md", "TASK-DRAFT.md"]
        for filename in fixedFiles {
            let path = (worktreePath as NSString).appendingPathComponent(filename)
            if let content = try? String(contentsOfFile: path, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let note = Note(
                    title: "[Archive] \(filename)",
                    content: content,
                    noteType: .archive
                )
                note.experiment = experiment
                context.insert(note)
                archived.append(filename)
            }
        }

        // .claude/plans/*.md
        let plansDir = (worktreePath as NSString).appendingPathComponent(".claude/plans")
        if let planFiles = try? fileManager.contentsOfDirectory(atPath: plansDir) {
            for filename in planFiles where filename.hasSuffix(".md") {
                let path = (plansDir as NSString).appendingPathComponent(filename)
                if let content = try? String(contentsOfFile: path, encoding: .utf8),
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let note = Note(
                        title: "[Archive] .claude/plans/\(filename)",
                        content: content,
                        noteType: .archive
                    )
                    note.experiment = experiment
                    context.insert(note)
                    archived.append(".claude/plans/\(filename)")
                }
            }
        }

        return archived
    }
}
