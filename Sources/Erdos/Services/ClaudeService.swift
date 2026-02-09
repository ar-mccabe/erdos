import Foundation

@Observable
@MainActor
final class ClaudeService {
    private var currentProcess: Process?

    /// Find the Claude CLI executable
    private var claudePath: String {
        // Check common locations
        let candidates = [
            NSHomeDirectory() + "/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "claude" // fallback to PATH
    }

    func streamResearch(
        prompt: String,
        workingDirectory: String?,
        resumeSessionId: String? = nil,
        model: String = "sonnet",
        maxBudget: Double = 2.0
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
                    "--model", model,
                    "--max-turns", "30",
                ]

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
