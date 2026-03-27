import Foundation
import AppKit
import SwiftTerm

class MonitoredTerminalView: LocalProcessTerminalView {
    /// Last time terminal received output from the process
    private(set) var lastOutputTime: Date?
    /// Whether the underlying process is still running
    private(set) var isProcessRunning = true

    // Deferred process start — waits for a non-zero frame so the PTY
    // is created with the correct terminal dimensions from the start.
    private var hasStartedProcess = false
    private var pendingStart: (
        executable: String, args: [String], env: [String],
        workingDirectory: String,
        initialCommand: String?, delayedInput: String?, delayedInputDelay: TimeInterval
    )?

    // MARK: - Kitty Keyboard Protocol workaround

    // SwiftTerm 1.12.0 supports the Kitty keyboard protocol. When Claude Code
    // enables it, functional keys (arrows, etc.) get encoded in the Kitty format
    // which produces garbled output. We install an NSEvent monitor to intercept
    // these keys and send standard xterm escape sequences instead.
    // (keyDown/keyUp can't be overridden because they aren't `open` in SwiftTerm.)
    nonisolated(unsafe) private var keyEventMonitor: Any?

    private func installKeyEventMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self = self,
                  self.window?.firstResponder === self,
                  !self.getTerminal().keyboardEnhancementFlags.isEmpty else {
                return event
            }

            if event.type == .keyUp {
                // Suppress Kitty key-release events that cause garbled output.
                return nil
            }

            // keyDown: intercept arrow keys and send standard xterm sequences
            guard let chars = event.charactersIgnoringModifiers,
                  let scalar = chars.unicodeScalars.first else {
                return event
            }

            let letter: UInt8
            switch Int(scalar.value) {
            case NSUpArrowFunctionKey:    letter = 0x41  // A
            case NSDownArrowFunctionKey:  letter = 0x42  // B
            case NSRightArrowFunctionKey: letter = 0x43  // C
            case NSLeftArrowFunctionKey:  letter = 0x44  // D
            default: return event
            }

            // Build xterm modifier parameter: 1 + (shift:1 + alt:2 + ctrl:4)
            let flags = event.modifierFlags
            var mod = 0
            if flags.contains(.shift)   { mod += 1 }
            if flags.contains(.option)  { mod += 2 }
            if flags.contains(.control) { mod += 4 }

            if mod == 0 {
                // Plain arrow — use standard or application-cursor sequence
                let app = self.getTerminal().applicationCursor
                let prefix: UInt8 = app ? 0x4f : 0x5b  // O or [
                self.send([0x1b, prefix, letter])
            } else {
                // Modified arrow — ESC [ 1 ; {mod+1} {letter}
                let param = UInt8(0x31 + mod)  // ASCII digit for mod+1 (2–8)
                self.send([0x1b, 0x5b, 0x31, 0x3b, param, letter])
            }
            return nil
        }
    }

    private func removeKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    deinit {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Deferred process start

    /// Configure the process to start once the view has a real frame.
    func configureDeferredStart(
        executable: String,
        args: [String],
        environment: [String],
        workingDirectory: String,
        initialCommand: String?,
        delayedInput: String?,
        delayedInputDelay: TimeInterval
    ) {
        pendingStart = (executable, args, environment, workingDirectory, initialCommand, delayedInput, delayedInputDelay)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        // Start the process on the first layout pass that gives us a real size.
        if !hasStartedProcess, newSize.width > 0, newSize.height > 0,
           let config = pendingStart {
            hasStartedProcess = true
            pendingStart = nil

            startProcess(
                executable: config.executable,
                args: config.args,
                environment: config.env,
                execName: nil
            )

            let cdCommand = "cd \"\(config.workingDirectory)\" && clear\n"
            send(txt: cdCommand)

            if let cmd = config.initialCommand {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.send(txt: cmd + "\n")
                }
            }

            if let input = config.delayedInput {
                let baseDelay = config.initialCommand != nil ? 0.5 + config.delayedInputDelay : config.delayedInputDelay
                DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay) { [weak self] in
                    self?.send(txt: input + "\n")
                }
            }

            installKeyEventMonitor()
        }
    }

    /// Force the PTY to match the current view dimensions.
    /// Call this after a tab switch to handle resizes that happened while hidden.
    func resyncPTYSize() {
        guard process.running, frame.width > 0, frame.height > 0 else { return }
        var size = getWindowSize()
        let _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: process.childfd, windowSize: &size)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        DispatchQueue.main.async { [weak self] in
            self?.lastOutputTime = Date()
        }
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        super.processTerminated(source, exitCode: exitCode)
        DispatchQueue.main.async { [weak self] in
            self?.isProcessRunning = false
        }
        removeKeyEventMonitor()
    }

    /// Kill the shell and all its child processes.
    /// SIGHUP tells zsh to forward the signal to all its jobs (foreground & background),
    /// which is how child processes like servers and Claude CLI get cleaned up.
    /// Plain SIGTERM only kills the shell — it doesn't propagate to child process groups.
    func terminateProcessGroup() {
        let pid = process.shellPid
        guard pid != 0 else { return }
        kill(pid, SIGHUP)
        // Clean up SwiftTerm's DispatchIO/fd state
        terminate()
    }
}
