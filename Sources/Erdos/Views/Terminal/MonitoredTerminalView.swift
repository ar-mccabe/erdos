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
}
