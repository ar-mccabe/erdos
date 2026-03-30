import SwiftUI

struct SettingsView: View {
    @Bindable var settings = ErdosSettings.shared
    @Environment(AppState.self) private var appState

    @State private var selectedRepo: RepoDiscoveryService.RepoInfo?
    @State private var repoConfig = ErdosConfig()
    @State private var initHook = ""
    @State private var promptPrefix = ""
    @State private var promptSuffix = ""
    @State private var repoModel = ""
    @State private var permissionMode = ""
    @State private var allowedTools = ""
    @State private var extraFlags = ""

    var body: some View {
        Form {
            Section("Paths") {
                LabeledContent("Worktree Directory") {
                    HStack {
                        TextField("", text: $settings.worktreeBasePath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            pickFolder { settings.worktreeBasePath = $0 }
                        }
                    }
                }
                Text("Isolated working directories for experiments are created here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Repo Scan Root") {
                    HStack {
                        TextField("", text: $settings.repoScanRoot)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            pickFolder { settings.repoScanRoot = $0 }
                        }
                    }
                }
                Text("Scanned on launch to find repositories for new experiments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Claude") {
                LabeledContent("Executable Path") {
                    TextField("", text: $settings.claudePath)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Path to the Claude Code CLI binary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Default Model", selection: $settings.defaultModel) {
                    ForEach(ErdosSettings.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            Section("Repository Defaults") {
                Picker("Repository", selection: $selectedRepo) {
                    Text("Select a repository...").tag(nil as RepoDiscoveryService.RepoInfo?)
                    ForEach(appState.repoDiscovery.repos) { repo in
                        Text(repo.name).tag(repo as RepoDiscoveryService.RepoInfo?)
                    }
                }

                if selectedRepo != nil {
                    LabeledContent("Init Hook") {
                        TextField("", text: $initHook, prompt: Text("e.g. make install && make db_seed"))
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("Bash command to run in the terminal after worktree creation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("Prompt Prefix") {
                        TextField("", text: $promptPrefix, prompt: Text("Prepended to the research plan prompt"))
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Prompt Suffix") {
                        TextField("", text: $promptSuffix, prompt: Text("Appended to the research plan prompt"))
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Model Override") {
                        TextField("", text: $repoModel, prompt: Text("e.g. claude-sonnet-4-5-20250929"))
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Permission Mode") {
                        TextField("", text: $permissionMode, prompt: Text("plan"))
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Allowed Tools") {
                        TextField("", text: $allowedTools, prompt: Text("Read,Glob,Grep,WebSearch,..."))
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Extra Flags") {
                        TextField("", text: $extraFlags, prompt: Text("e.g. --max-turns 50"))
                            .textFieldStyle(.roundedBorder)
                    }

                    Text("These settings are stored in the repo's .erdos.yml file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: selectedRepo != nil ? 700 : 350)
        .navigationTitle("Settings")
        .onChange(of: selectedRepo) { _, newRepo in
            loadRepoConfig(for: newRepo)
        }
        .onChange(of: initHook) { _, _ in saveRepoConfig() }
        .onChange(of: promptPrefix) { _, _ in saveRepoConfig() }
        .onChange(of: promptSuffix) { _, _ in saveRepoConfig() }
        .onChange(of: repoModel) { _, _ in saveRepoConfig() }
        .onChange(of: permissionMode) { _, _ in saveRepoConfig() }
        .onChange(of: allowedTools) { _, _ in saveRepoConfig() }
        .onChange(of: extraFlags) { _, _ in saveRepoConfig() }
    }

    private func loadRepoConfig(for repo: RepoDiscoveryService.RepoInfo?) {
        guard let repo else {
            repoConfig = ErdosConfig()
            clearFields()
            return
        }
        repoConfig = ErdosConfig.load(repoPath: repo.path) ?? ErdosConfig()
        initHook = repoConfig.worktree?.initHook ?? ""
        promptPrefix = repoConfig.researchPlan?.promptPrefix ?? ""
        promptSuffix = repoConfig.researchPlan?.promptSuffix ?? ""
        repoModel = repoConfig.researchPlan?.model ?? ""
        permissionMode = repoConfig.researchPlan?.permissionMode ?? ""
        allowedTools = repoConfig.researchPlan?.allowedTools ?? ""
        extraFlags = repoConfig.researchPlan?.extraFlags ?? ""
    }

    private func clearFields() {
        initHook = ""
        promptPrefix = ""
        promptSuffix = ""
        repoModel = ""
        permissionMode = ""
        allowedTools = ""
        extraFlags = ""
    }

    private func saveRepoConfig() {
        guard let repo = selectedRepo else { return }

        // Update worktree config
        let hookValue = initHook.isEmpty ? nil : initHook
        if hookValue != nil || repoConfig.worktree != nil {
            if repoConfig.worktree == nil {
                repoConfig.worktree = ErdosConfig.WorktreeConfig()
            }
            repoConfig.worktree?.initHook = hookValue
        }

        // Update research plan config
        let hasResearchPlan = !promptPrefix.isEmpty || !promptSuffix.isEmpty
            || !repoModel.isEmpty || !permissionMode.isEmpty
            || !allowedTools.isEmpty || !extraFlags.isEmpty
        if hasResearchPlan || repoConfig.researchPlan != nil {
            if repoConfig.researchPlan == nil {
                repoConfig.researchPlan = ErdosConfig.ResearchPlanConfig()
            }
            repoConfig.researchPlan?.promptPrefix = promptPrefix.isEmpty ? nil : promptPrefix
            repoConfig.researchPlan?.promptSuffix = promptSuffix.isEmpty ? nil : promptSuffix
            repoConfig.researchPlan?.model = repoModel.isEmpty ? nil : repoModel
            repoConfig.researchPlan?.permissionMode = permissionMode.isEmpty ? nil : permissionMode
            repoConfig.researchPlan?.allowedTools = allowedTools.isEmpty ? nil : allowedTools
            repoConfig.researchPlan?.extraFlags = extraFlags.isEmpty ? nil : extraFlags
        }

        // Clean up empty sections
        if let w = repoConfig.worktree,
           w.copyFiles == nil && w.envVar == nil && w.initHook == nil {
            repoConfig.worktree = nil
        }
        if let r = repoConfig.researchPlan,
           r.promptPrefix == nil && r.promptSuffix == nil && r.model == nil
            && r.permissionMode == nil && r.allowedTools == nil && r.extraFlags == nil {
            repoConfig.researchPlan = nil
        }

        repoConfig.save(repoPath: repo.path)
    }

    private func pickFolder(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }
}
