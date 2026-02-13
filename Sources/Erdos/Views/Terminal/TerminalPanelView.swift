import SwiftUI
import SwiftTerm

struct TerminalPanelView: View {
    let experiment: Experiment
    @Binding var hasWaitingClaudeSession: Bool
    @Environment(AppState.self) private var appState
    @State private var tabs: [TerminalTab] = []
    @State private var selectedTabId: UUID?
    @State private var terminalViews: [UUID: MonitoredTerminalView] = [:]
    @State private var idleCheckTimer: Timer?

    struct TerminalTab: Identifiable {
        let id = UUID()
        var label: String
        var initialCommand: String?
        var delayedInput: String?

        var isClaudeTab: Bool {
            label.localizedCaseInsensitiveContains("claude")
                || (initialCommand?.localizedCaseInsensitiveContains("claude") ?? false)
        }
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

                if let id = selectedTabId, terminalViews[id] != nil {
                    Button {
                        resetTerminal(id)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Reset terminal display")
                }

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

            // Terminal content — ZStack keeps all sessions alive across tab switches
            ZStack {
                ForEach(tabs) { tab in
                    TerminalRepresentable(
                        workingDirectory: experiment.worktreePath ?? experiment.repoPath,
                        initialCommand: tab.initialCommand,
                        delayedInput: tab.delayedInput,
                        terminalView: Binding(
                            get: { terminalViews[tab.id] },
                            set: { newValue in
                                if let old = terminalViews[tab.id] {
                                    appState.unregisterTerminal(old)
                                }
                                terminalViews[tab.id] = newValue
                                if let tv = newValue {
                                    appState.registerTerminal(tv)
                                }
                            }
                        )
                    )
                    .opacity(selectedTabId == tab.id ? 1 : 0)
                    .allowsHitTesting(selectedTabId == tab.id)
                }
            }
        }
        .onAppear {
            if tabs.isEmpty {
                addTab()
            }
            startIdleCheckTimer()
        }
        .onDisappear {
            idleCheckTimer?.invalidate()
            idleCheckTimer = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchClaude)) { notification in
            // Only handle notifications targeted at this experiment
            if let targetId = notification.userInfo?["experimentId"] as? String,
               targetId != experiment.id.uuidString {
                return
            }

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

    private func resetTerminal(_ id: UUID) {
        guard let terminal = terminalViews[id] else { return }
        terminal.send(txt: "\u{1b}c")  // ESC c — full terminal reset
    }

    private func closeTab(_ id: UUID) {
        if let terminal = terminalViews[id] {
            if terminal.isProcessRunning {
                terminal.terminateProcessGroup()
            }
            appState.unregisterTerminal(terminal)
        }
        tabs.removeAll { $0.id == id }
        terminalViews.removeValue(forKey: id)
        if selectedTabId == id {
            selectedTabId = tabs.last?.id
        }
    }

    private func startIdleCheckTimer() {
        idleCheckTimer?.invalidate()
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            DispatchQueue.main.async {
                checkForIdleClaude()
            }
        }
    }

    private func checkForIdleClaude() {
        let now = Date()
        let idleThreshold: TimeInterval = 30

        let waiting = tabs.contains { tab in
            guard tab.isClaudeTab,
                  let terminal = terminalViews[tab.id],
                  terminal.isProcessRunning,
                  let lastOutput = terminal.lastOutputTime else {
                return false
            }
            return now.timeIntervalSince(lastOutput) > idleThreshold
        }

        hasWaitingClaudeSession = waiting
    }
}
