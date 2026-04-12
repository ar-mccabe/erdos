import SwiftUI
import SwiftTerm

struct AdHocTerminalView: View {
    @Environment(AppState.self) private var appState
    @State private var tabs: [TerminalTab] = []
    @State private var selectedTabId: UUID?
    @State private var terminalViews: [UUID: MonitoredTerminalView] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    Button {
                        selectedTabId = tab.id
                        if let terminal = terminalViews[tab.id] {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                terminal.resyncPTYSize()
                            }
                        }
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
                        workingDirectory: NSHomeDirectory(),
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
        }
    }

    private func addTab(label: String = "zsh", command: String? = nil) {
        let tab = TerminalTab(label: label, initialCommand: command)
        tabs.append(tab)
        selectedTabId = tab.id
    }

    private func resetTerminal(_ id: UUID) {
        guard let terminal = terminalViews[id] else { return }
        terminal.send(txt: "\u{1b}c")
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
}
