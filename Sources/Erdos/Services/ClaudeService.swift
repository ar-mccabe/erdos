import Foundation

enum ResearchPermissionMode: String, CaseIterable, Identifiable {
    case readAndWeb       // Default: read code + search web, no writes
    case readOnly         // Read code only, no web
    case fullAccess       // Can read, write, execute — use with caution

    var id: String { rawValue }

    var label: String {
        switch self {
        case .readAndWeb: "Read + Web (Recommended)"
        case .readOnly: "Read Only"
        case .fullAccess: "Full Access"
        }
    }

    var description: String {
        switch self {
        case .readAndWeb: "Can read code and search the web. Cannot edit files or run commands."
        case .readOnly: "Can only read code. No web access, no edits."
        case .fullAccess: "Can read, edit, run commands, and search the web. Use with caution."
        }
    }

    var cliArgs: [String] {
        switch self {
        case .readAndWeb:
            return [
                "--permission-mode", "plan",
                "--allowed-tools", "Read,Glob,Grep,WebSearch,WebFetch,Task",
            ]
        case .readOnly:
            return [
                "--permission-mode", "plan",
            ]
        case .fullAccess:
            return [
                "--permission-mode", "bypassPermissions",
            ]
        }
    }
}

@Observable
@MainActor
final class ClaudeService {
    private var currentProcess: Process?

    private var claudePath: String { ErdosSettings.shared.claudePath }

    func streamResearch(
        prompt: String,
        workingDirectory: String?,
        resumeSessionId: String? = nil,
        model: String = "sonnet",
        permissionMode: ResearchPermissionMode = .readAndWeb,
        maxBudget: Double = 2.0,
        maxTurns: Int = 30
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let claudeExe = claudePath
        let cwd = workingDirectory

        return AsyncThrowingStream { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: claudeExe)

                var args = [
                    "-p", prompt,
                    "--output-format", "stream-json",
                    "--verbose",
                    "--model", model,
                    "--max-turns", "\(maxTurns)",
                ]

                // Apply permission mode
                args += permissionMode.cliArgs

                if let sessionId = resumeSessionId {
                    args += ["--resume", sessionId]
                }

                process.arguments = args

                if let cwd {
                    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                }

                // Inherit environment so claude finds its config
                process.environment = ProcessInfo.processInfo.environment

                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe

                await MainActor.run {
                    self.currentProcess = process
                }

                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                let handle = pipe.fileHandleForReading

                // Read line by line
                var buffer = Data()
                while process.isRunning || handle.availableData.count > 0 {
                    let data = handle.availableData
                    if data.isEmpty {
                        if !process.isRunning { break }
                        try? await Task.sleep(for: .milliseconds(50))
                        continue
                    }

                    buffer.append(data)

                    // Process complete lines
                    while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                        buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                        if let line = String(data: lineData, encoding: .utf8),
                           let event = StreamJSONParser.parse(line: line) {
                            continuation.yield(event)
                        }
                    }
                }

                // Process remaining buffer
                if !buffer.isEmpty,
                   let line = String(data: buffer, encoding: .utf8),
                   let event = StreamJSONParser.parse(line: line) {
                    continuation.yield(event)
                }

                // Check for errors
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus != 0 {
                    let errorMsg = String(data: errorData, encoding: .utf8) ?? "Claude process exited with code \(process.terminationStatus)"
                    continuation.yield(.error(errorMsg))
                }

                await MainActor.run {
                    self.currentProcess = nil
                }
                continuation.finish()
            }
        }
    }

    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
    }
}
