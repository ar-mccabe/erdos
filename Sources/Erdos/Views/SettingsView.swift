import SwiftUI

struct SettingsView: View {
    @Bindable var settings = ErdosSettings.shared

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
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 350)
        .navigationTitle("Settings")
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
