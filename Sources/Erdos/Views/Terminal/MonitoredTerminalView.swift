import Foundation
import SwiftTerm

class MonitoredTerminalView: LocalProcessTerminalView {
    /// Last time terminal received output from the process
    private(set) var lastOutputTime: Date?
    /// Whether the underlying process is still running
    private(set) var isProcessRunning = true

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        DispatchQueue.main.async {
            self.lastOutputTime = Date()
        }
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        super.processTerminated(source, exitCode: exitCode)
        DispatchQueue.main.async {
            self.isProcessRunning = false
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
