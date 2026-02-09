import SwiftUI
import SwiftTerm

struct TerminalPanelView: View {
    let experiment: Experiment
    @State private var tabs: [TerminalTab] = []
    @State private var selectedTabId: UUID?
    @State private var terminalViews: [UUID: LocalProcessTerminalView] = [:]

    struct TerminalTab: Identifiable {
        let id = UUID()
        var label: String
        var initialCommand: String?
        var delayedInput: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    Button {
                        selectedTabId = tab.id
                    } label: {
                        HStack(spacing: 4) {
                            Text(tab.label)
                                .font(.caption)
                            if tabs.count > 1 {
                                Button {
                                    closeTab(tab.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8))
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selectedTabId == tab.id ? Color.accentColor.opacity(0.1) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    addTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)

                Spacer()

                Button("Claude") {
                    addTab(label: "Claude", command: "claude")
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.bar)

            // Terminal content
            if let selectedId = selectedTabId,
               let tab = tabs.first(where: { $0.id == selectedId }) {
                TerminalRepresentable(
                    workingDirectory: experiment.worktreePath ?? experiment.repoPath,
                    initialCommand: tab.initialCommand,
                    delayedInput: tab.delayedInput,
                    terminalView: Binding(
                        get: { terminalViews[tab.id] },
                        set: { terminalViews[tab.id] = $0 }
                    )
                )
                .id(tab.id) // Force new view per tab
            }
        }
        .onAppear {
            if tabs.isEmpty {
                addTab()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchClaude)) { notification in
            if let prompt = notification.userInfo?["prompt"] as? String {
                // Interactive claude with a prompt typed in after launch
                let label = notification.userInfo?["label"] as? String ?? "Claude"
                addTab(label: label, command: "claude", delayedInput: prompt)
            } else if let command = notification.userInfo?["command"] as? String {
                // Custom command
                let label = notification.userInfo?["label"] as? String ?? "Claude"
                addTab(label: label, command: command)
            } else if let sessionId = notification.userInfo?["sessionId"] as? String {
                addTab(label: "Claude (resume)", command: "claude --resume \(sessionId)")
            } else {
                addTab(label: "Claude", command: "claude")
            }
        }
    }

    private func addTab(label: String = "zsh", command: String? = nil, delayedInput: String? = nil) {
        let tab = TerminalTab(label: label, initialCommand: command, delayedInput: delayedInput)
        tabs.append(tab)
        selectedTabId = tab.id
    }

    private func closeTab(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        terminalViews.removeValue(forKey: id)
        if selectedTabId == id {
            selectedTabId = tabs.last?.id
        }
    }
}
