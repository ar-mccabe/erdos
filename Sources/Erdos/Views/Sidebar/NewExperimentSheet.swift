import SwiftUI
import SwiftData

struct NewExperimentSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var hypothesis = ""
    @State private var detail = ""
    @State private var selectedRepo: RepoDiscoveryService.RepoInfo?
    @State private var baseBranch = "main"
    @State private var branchName = ""
    @State private var status: ExperimentStatus = .idea
    @State private var tagsText = ""

    @State private var branches: [GitService.BranchInfo] = []
    @State private var isLoadingBranches = false
    @State private var createWorktree = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Experiment")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Basics") {
                    TextField("Title", text: $title, prompt: Text("e.g. Slack activity scoring model"))
                    TextField("Hypothesis", text: $hypothesis, prompt: Text("What are you exploring?"))
                        .lineLimit(2...4)
                    TextField("Detail", text: $detail, prompt: Text("Additional context (markdown)"), axis: .vertical)
                        .lineLimit(3...8)
                    Picker("Initial Status", selection: $status) {
                        ForEach([ExperimentStatus.idea, .researching, .planned, .active]) { s in
                            Label(s.label, systemImage: s.icon).tag(s)
                        }
                    }
                    TextField("Tags (comma-separated)", text: $tagsText, prompt: Text("ml, scoring, slack"))
                }

                Section("Repository") {
                    Picker("Repository", selection: $selectedRepo) {
                        Text("None").tag(nil as RepoDiscoveryService.RepoInfo?)
                        ForEach(appState.repoDiscovery.repos) { repo in
                            Text(repo.name).tag(repo as RepoDiscoveryService.RepoInfo?)
                        }
                    }

                    if selectedRepo != nil {
                        Picker("Base Branch", selection: $baseBranch) {
                            ForEach(branches) { branch in
                                Text(branch.name).tag(branch.name)
                            }
                        }
                        .disabled(isLoadingBranches)

                        TextField("New Branch Name", text: $branchName, prompt: Text("auto-generated from title"))

                        Toggle("Create worktree immediately", isOn: $createWorktree)
                            .help("Creates an isolated working directory for this experiment")
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 400)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Create Experiment") {
                    Task { await createExperiment() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 550, height: 600)
        .onChange(of: selectedRepo) { _, newRepo in
            if let repo = newRepo {
                loadBranches(for: repo)
            } else {
                branches = []
            }
        }
    }

    private func loadBranches(for repo: RepoDiscoveryService.RepoInfo) {
        isLoadingBranches = true
        Task {
            do {
                branches = try await appState.gitService.listBranches(repoPath: repo.path)
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
    }

    private func createExperiment() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let effectiveBranch = branchName.isEmpty
            ? SlugGenerator.generate(from: trimmedTitle)
            : branchName

        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let experiment = Experiment(
            title: trimmedTitle,
            hypothesis: hypothesis,
            detail: detail,
            status: status,
            repoPath: selectedRepo?.path ?? "",
            branchName: selectedRepo != nil ? effectiveBranch : nil,
            baseBranch: selectedRepo != nil ? baseBranch : nil,
            tags: tags
        )

        modelContext.insert(experiment)

        // Create worktree if requested
        if createWorktree, let repo = selectedRepo {
            do {
                let worktreePath = try await appState.gitService.createWorktree(
                    repoPath: repo.path,
                    branchName: effectiveBranch,
                    baseBranch: baseBranch
                )
                experiment.worktreePath = worktreePath

                let event = TimelineEvent(
                    eventType: .branchCreated,
                    summary: "Created branch '\(effectiveBranch)' with worktree"
                )
                event.experiment = experiment
                modelContext.insert(event)
            } catch {
                self.error = "Experiment created, but worktree failed: \(error.localizedDescription)"
                return
            }
        }

        // Add creation timeline event
        let event = TimelineEvent(
            eventType: .statusChange,
            summary: "Experiment created with status: \(status.label)"
        )
        event.experiment = experiment
        modelContext.insert(event)

        try? modelContext.save()
        appState.selectedExperiment = experiment
        dismiss()
    }
}
