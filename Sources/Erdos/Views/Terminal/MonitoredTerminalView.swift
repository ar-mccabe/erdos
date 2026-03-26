import Foundation
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
