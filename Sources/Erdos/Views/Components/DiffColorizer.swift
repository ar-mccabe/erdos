import SwiftUI

enum DiffColorizer {
    static func coloredDiff(_ text: String) -> AttributedString {
        var result = AttributedString()

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var attrLine = AttributedString(line + "\n")

            if line.hasPrefix("+++ ") || line.hasPrefix("--- ") {
                attrLine.foregroundColor = .secondary
                attrLine.font = .system(.caption, design: .monospaced).bold()
            } else if line.hasPrefix("diff --git") {
                attrLine.foregroundColor = .blue
                attrLine.font = .system(.caption, design: .monospaced).bold()
            } else if line.hasPrefix("@@") {
                attrLine.foregroundColor = .cyan
            } else if line.hasPrefix("+") {
                attrLine.foregroundColor = .green
                attrLine.backgroundColor = .green.opacity(0.1)
            } else if line.hasPrefix("-") {
                attrLine.foregroundColor = .red
                attrLine.backgroundColor = .red.opacity(0.1)
            }

            result.append(attrLine)
        }

        return result
    }
}
