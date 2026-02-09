import SwiftUI
import SwiftTerm

struct TerminalRepresentable: NSViewRepresentable {
    let workingDirectory: String
    let initialCommand: String?
    /// Text to send as input after the initial command has launched (e.g. a prompt to type into claude)
    let delayedInput: String?
    let delayedInputDelay: TimeInterval
    @Binding var terminalView: LocalProcessTerminalView?

    init(
        workingDirectory: String,
        initialCommand: String? = nil,
        delayedInput: String? = nil,
        delayedInputDelay: TimeInterval = 2.0,
        terminalView: Binding<LocalProcessTerminalView?>
    ) {
        self.workingDirectory = workingDirectory
        self.initialCommand = initialCommand
        self.delayedInput = delayedInput
        self.delayedInputDelay = delayedInputDelay
        self._terminalView = terminalView
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)

        // Configure appearance
        terminal.nativeForegroundColor = .textColor
        terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Get shell path
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // Start the process
        terminal.startProcess(
            executable: shell,
            args: [],
            environment: nil,
            execName: nil
        )

        // cd to working directory
        let cdCommand = "cd \"\(workingDirectory)\" && clear\n"
        terminal.send(txt: cdCommand)

        // Execute initial command if provided
        if let cmd = initialCommand {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                terminal.send(txt: cmd + "\n")
            }
        }

        // Send delayed input (e.g. prompt text into an interactive claude session)
        if let input = delayedInput {
            let baseDelay = initialCommand != nil ? 0.5 + delayedInputDelay : delayedInputDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay) {
                terminal.send(txt: input + "\n")
            }
        }

        DispatchQueue.main.async {
            self.terminalView = terminal
        }

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No updates needed - terminal manages its own state
    }
}
