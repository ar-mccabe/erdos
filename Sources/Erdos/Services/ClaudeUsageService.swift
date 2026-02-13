import Foundation

struct ClaudeUsage: Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var costUSD: Double = 0
}

/// Reads Claude session JSONL files from ~/.claude/projects/ to aggregate token usage and cost
/// for experiments that ran Claude via the terminal.
enum ClaudeUsageService {

    static func loadUsage(forPath path: String) async -> ClaudeUsage {
        await Task.detached {
            let projectDir = claudeProjectDir(for: path)
            guard FileManager.default.fileExists(atPath: projectDir) else { return ClaudeUsage() }

            let sessionFiles = (try? FileManager.default.contentsOfDirectory(atPath: projectDir))?.filter { $0.hasSuffix(".jsonl") } ?? []

            var totals: [String: ClaudeUsage] = [:]

            for file in sessionFiles {
                let filePath = (projectDir as NSString).appendingPathComponent(file)
                guard let handle = FileHandle(forReadingAtPath: filePath) else { continue }
                defer { handle.closeFile() }

                let data = handle.readDataToEndOfFile()
                guard let content = String(data: data, encoding: .utf8) else { continue }

                for line in content.split(separator: "\n") where line.contains("\"usage\"") {
                    guard let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                          let message = json["message"] as? [String: Any],
                          let usage = message["usage"] as? [String: Any],
                          let model = message["model"] as? String else { continue }

                    let input = usage["input_tokens"] as? Int ?? 0
                    let output = usage["output_tokens"] as? Int ?? 0
                    let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                    let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0

                    var entry = totals[model, default: ClaudeUsage()]
                    entry.inputTokens += input
                    entry.outputTokens += output
                    entry.cacheReadTokens += cacheRead
                    entry.cacheWriteTokens += cacheWrite
                    totals[model] = entry
                }
            }

            // Compute cost per model, then aggregate
            var result = ClaudeUsage()
            for (model, usage) in totals {
                let rates = modelRates(for: model)
                let cost = Double(usage.inputTokens) * rates.input
                    + Double(usage.outputTokens) * rates.output
                    + Double(usage.cacheReadTokens) * rates.cacheRead
                    + Double(usage.cacheWriteTokens) * rates.cacheWrite

                result.inputTokens += usage.inputTokens
                result.outputTokens += usage.outputTokens
                result.cacheReadTokens += usage.cacheReadTokens
                result.cacheWriteTokens += usage.cacheWriteTokens
                result.costUSD += cost
            }
            return result
        }.value
    }

    // MARK: - Private

    private static func claudeProjectDir(for path: String) -> String {
        let dirName = path.replacingOccurrences(of: "/", with: "-")
        return NSHomeDirectory() + "/.claude/projects/" + dirName
    }

    /// Per-token rates (USD) for known Claude models.
    private static func modelRates(for model: String) -> (input: Double, output: Double, cacheRead: Double, cacheWrite: Double) {
        let perM: (Double, Double, Double, Double) = {
            if model.contains("opus-4-6") || model.contains("opus-4-5") || model.contains("opus-4.6") || model.contains("opus-4.5") {
                return (5, 25, 0.50, 6.25)
            } else if model.contains("opus") {
                return (15, 75, 1.50, 18.75)
            } else if model.contains("sonnet") {
                return (3, 15, 0.30, 3.75)
            } else if model.contains("haiku-4-5") || model.contains("haiku-4.5") || model.contains("haiku4.5") {
                return (1, 5, 0.10, 1.25)
            } else if model.contains("haiku") {
                return (0.80, 4, 0.08, 1.00)
            } else {
                // Default to sonnet-class pricing
                return (3, 15, 0.30, 3.75)
            }
        }()

        return (perM.0 / 1_000_000, perM.1 / 1_000_000, perM.2 / 1_000_000, perM.3 / 1_000_000)
    }
}
