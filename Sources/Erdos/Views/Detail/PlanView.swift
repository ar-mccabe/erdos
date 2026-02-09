import SwiftUI

struct PlanView: View {
    @Bindable var experiment: Experiment
    @State private var isEditing = false
    @State private var editContent = ""
    @State private var planContent = ""
    @State private var planFilePath: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if planFilePath != nil {
                    Button(isEditing ? "Preview" : "Edit") {
                        if isEditing {
                            savePlan()
                        } else {
                            editContent = planContent
                        }
                        isEditing.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                Button("Refresh") {
                    Task { await loadPlan() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if isEditing {
                TextEditor(text: $editContent)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
            } else if planContent.isEmpty {
                ContentUnavailableView {
                    Label("No Plan Yet", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("Start a research session to generate a plan, or create a PLAN.md in the worktree.")
                }
            } else {
                MarkdownContentView(content: planContent)
            }
        }
        .task { await loadPlan() }
    }

    private func loadPlan() async {
        guard let worktree = experiment.worktreePath else {
            planContent = experiment.detail
            return
        }

        let candidates = ["PLAN.md", "plan.md", "CLAUDE.md", "README.md"]
        let fm = FileManager.default

        for candidate in candidates {
            let path = (worktree as NSString).appendingPathComponent(candidate)
            if fm.fileExists(atPath: path),
               let content = try? String(contentsOfFile: path, encoding: .utf8) {
                planContent = content
                planFilePath = path
                return
            }
        }

        planContent = experiment.detail
    }

    private func savePlan() {
        if let path = planFilePath {
            try? editContent.write(toFile: path, atomically: true, encoding: .utf8)
            planContent = editContent
        } else {
            experiment.detail = editContent
            planContent = editContent
        }
    }
}
