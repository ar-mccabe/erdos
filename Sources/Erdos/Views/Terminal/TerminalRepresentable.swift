import SwiftUI
import SwiftTerm

struct TerminalRepresentable: NSViewRepresentable {
    let workingDirectory: String
    let initialCommand: String?
    /// Text to send as input after the initial command has launched (e.g. a prompt to type into claude)
    let delayedInput: String?
    let delayedInputDelay: TimeInterval
    @Binding var terminalView: MonitoredTerminalView?

    init(
        workingDirectory: String,
        initialCommand: String? = nil,
        delayedInput: String? = nil,
        delayedInputDelay: TimeInterval = 2.0,
        terminalView: Binding<MonitoredTerminalView?>
    ) {
        self.workingDirectory = workingDirectory
        self.initialCommand = initialCommand
        self.delayedInput = delayedInput
        self.delayedInputDelay = delayedInputDelay
        self._terminalView = terminalView
    }

    func makeNSView(context: Context) -> MonitoredTerminalView {
        let terminal = MonitoredTerminalView(frame: .zero)

        // Configure appearance and scrollback
        terminal.nativeForegroundColor = .textColor
        terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.getTerminal().changeHistorySize(5_000)

        // Get shell path
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // Build environment with enriched PATH (app bundles get a minimal one)
        var enriched = ProcessRunner.enrichedEnvironment()
        // App bundles lack TERM; SwiftTerm needs it for the shell to behave
        if enriched["TERM"] == nil {
            enriched["TERM"] = "xterm-256color"
        }
        let env = enriched.map { "\($0.key)=\($0.value)" }

        // Defer process start until the view has a non-zero frame.
        // This ensures the PTY is created with the correct terminal dimensions,
        // preventing garbled rendering in TUI apps like Claude Code.
        terminal.configureDeferredStart(
            executable: shell,
            args: [],
            environment: env,
            workingDirectory: workingDirectory,
            initialCommand: initialCommand,
            delayedInput: delayedInput,
            delayedInputDelay: delayedInputDelay
        )

        DispatchQueue.main.async {
            self.terminalView = terminal
        }

        return terminal
    }

    func updateNSView(_ nsView: MonitoredTerminalView, context: Context) {
        // No updates needed - terminal manages its own state
    }
}
