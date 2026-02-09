import Foundation

enum ClaudeStreamEvent: Sendable {
    case text(String)
    case sessionId(String)
    case result(costUSD: Double, inputTokens: Int, outputTokens: Int)
    case error(String)
}

struct StreamJSONParser {
    /// Parse a single line of NDJSON from Claude's stream-json output
    static func parse(line: String) -> ClaudeStreamEvent? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let type = json["type"] as? String else { return nil }

        switch type {
        case "assistant":
            // Extract text from content blocks
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                var text = ""
                for block in content {
                    if block["type"] as? String == "text",
                       let blockText = block["text"] as? String {
                        text += blockText
                    }
                }
                if !text.isEmpty { return .text(text) }
            }
            return nil

        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                return .text(text)
            }
            return nil

        case "system":
            if let sessionId = json["session_id"] as? String {
                return .sessionId(sessionId)
            }
            // Also check for subtype
            if let subtype = json["subtype"] as? String, subtype == "init",
               let sessionId = json["session_id"] as? String {
                return .sessionId(sessionId)
            }
            return nil

        case "result":
            let cost = json["cost_usd"] as? Double ?? 0
            let inputTokens = json["input_tokens"] as? Int ?? 0
            let outputTokens = json["output_tokens"] as? Int ?? 0
            // Try nested stats
            if let stats = json["usage"] as? [String: Any] {
                let input = stats["input_tokens"] as? Int ?? inputTokens
                let output = stats["output_tokens"] as? Int ?? outputTokens
                return .result(costUSD: cost, inputTokens: input, outputTokens: output)
            }
            return .result(costUSD: cost, inputTokens: inputTokens, outputTokens: outputTokens)

        case "error":
            let message = json["error"] as? String ?? json["message"] as? String ?? "Unknown error"
            return .error(message)

        default:
            return nil
        }
    }
}
