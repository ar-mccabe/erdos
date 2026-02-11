import SwiftUI
import SwiftData

struct NewExperimentSheet: View {
    enum BranchMode: String, CaseIterable {
        case createNew = "New Branch"
        case useExisting = "Existing Branch"
    }

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

    @State private var branchMode: BranchMode = .createNew
    @State private var selectedExistingBranch: String = ""
    @Query private var allExperiments: [Experiment]

    private var claimedBranchNames: Set<String> {
        guard let repo = selectedRepo else { return [] }
        let terminal: Set<String> = [ExperimentStatus.completed.rawValue, ExperimentStatus.abandoned.rawValue]
        return Set(
            allExperiments
                .filter { $0.repoPath == repo.path && !terminal.contains($0.statusRaw) && $0.branchName != nil }
                .compactMap(\.branchName)
        )
    }

    private var availableBranches: [GitService.BranchInfo] {
        branches.filter { !claimedBranchNames.contains($0.name) }
    }

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
                        ForEach([ExperimentStatus.idea, .researching, .planned, .implementing]) { s in
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
                        Picker("Branch", selection: $branchMode) {
                            ForEach(BranchMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        switch branchMode {
                        case .createNew:
                            Picker("Base Branch", selection: $baseBranch) {
                                ForEach(branches) { branch in
                                    Text(branch.name).tag(branch.name)
                                }
                            }
                            .disabled(isLoadingBranches)

                            TextField("New Branch Name", text: $branchName, prompt: Text("auto-generated from title"))

                        case .useExisting:
                            if availableBranches.isEmpty {
                                Text("No available branches")
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("Branch", selection: $selectedExistingBranch) {
                                    Text("Select a branch…").tag("")
                                    ForEach(availableBranches) { branch in
                                        Text(branch.name).tag(branch.name)
                                    }
                                }
                                .disabled(isLoadingBranches)
                            }
                        }

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
                .disabled(
                    title.trimmingCharacters(in: .whitespaces).isEmpty ||
                    (selectedRepo != nil && branchMode == .useExisting && selectedExistingBranch.isEmpty)
                )
            }
            .padding()
        }
        .frame(width: 550, height: 600)
        .onChange(of: selectedRepo) { _, newRepo in
            branchMode = .createNew
            selectedExistingBranch = ""
            branchName = ""
            if let repo = newRepo {
                loadBranches(for: repo)
            } else {
                branches = []
            }
        }
        .onChange(of: branchMode) { _, _ in
            selectedExistingBranch = ""
            branchName = ""
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

        let effectiveBranch: String
        let effectiveBaseBranch: String?

        if selectedRepo != nil {
            switch branchMode {
            case .createNew:
                effectiveBranch = branchName.isEmpty
                    ? SlugGenerator.generate(from: trimmedTitle)
                    : branchName
                effectiveBaseBranch = baseBranch
            case .useExisting:
                guard !selectedExistingBranch.isEmpty else { return }
                guard !claimedBranchNames.contains(selectedExistingBranch) else {
                    self.error = "Branch '\(selectedExistingBranch)' is already used by another active experiment."
                    return
                }
                effectiveBranch = selectedExistingBranch
                effectiveBaseBranch = nil
            }
        } else {
            effectiveBranch = ""
            effectiveBaseBranch = nil
        }

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
            baseBranch: effectiveBaseBranch,
            tags: tags
        )

        modelContext.insert(experiment)

        // Create worktree if requested
        if createWorktree, let repo = selectedRepo {
            do {
                let worktreePath = try await appState.gitService.createWorktree(
                    repoPath: repo.path,
                    branchName: effectiveBranch,
                    baseBranch: effectiveBaseBranch ?? baseBranch
                )
                experiment.worktreePath = worktreePath

                let summary = branchMode == .useExisting
                    ? "Created worktree for existing branch '\(effectiveBranch)'"
                    : "Created branch '\(effectiveBranch)' with worktree"
                let event = TimelineEvent(
                    eventType: .branchCreated,
                    summary: summary
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
