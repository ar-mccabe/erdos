import SwiftUI

enum DiffColorizer {
    // MARK: - Structured Diff Parsing

    enum DiffLineType {
        case header      // diff --git, ---, +++
        case hunkHeader  // @@ ... @@
        case added
        case removed
        case context
    }

    struct DiffLine: Identifiable {
        let id: Int
        let type: DiffLineType
        let content: String
        let oldLineNumber: Int?
        let newLineNumber: Int?
    }

    static func parseDiff(_ text: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var oldLine = 0
        var newLine = 0
        var lineId = 0

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("diff --git") || line.hasPrefix("--- ") || line.hasPrefix("+++ ") ||
               line.hasPrefix("index ") || line.hasPrefix("new file") || line.hasPrefix("deleted file") {
                lines.append(DiffLine(id: lineId, type: .header, content: line,
                                      oldLineNumber: nil, newLineNumber: nil))
            } else if line.hasPrefix("@@") {
                // Parse hunk header: @@ -old,count +new,count @@
                let numbers = parseHunkHeader(line)
                oldLine = numbers.oldStart
                newLine = numbers.newStart
                lines.append(DiffLine(id: lineId, type: .hunkHeader, content: line,
                                      oldLineNumber: nil, newLineNumber: nil))
            } else if line.hasPrefix("+") {
                lines.append(DiffLine(id: lineId, type: .added, content: String(line.dropFirst()),
                                      oldLineNumber: nil, newLineNumber: newLine))
                newLine += 1
            } else if line.hasPrefix("-") {
                lines.append(DiffLine(id: lineId, type: .removed, content: String(line.dropFirst()),
                                      oldLineNumber: oldLine, newLineNumber: nil))
                oldLine += 1
            } else {
                // Context line (may have leading space)
                let content = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                lines.append(DiffLine(id: lineId, type: .context, content: content,
                                      oldLineNumber: oldLine, newLineNumber: newLine))
                oldLine += 1
                newLine += 1
            }

            lineId += 1
        }

        return lines
    }

    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, newStart: Int) {
        // Format: @@ -oldStart[,oldCount] +newStart[,newCount] @@
        let scanner = Scanner(string: line)
        _ = scanner.scanString("@@")
        _ = scanner.scanString("-")
        let oldStart = scanner.scanInt() ?? 1
        // Skip optional ,count
        if scanner.scanString(",") != nil {
            _ = scanner.scanInt()
        }
        _ = scanner.scanString("+")
        let newStart = scanner.scanInt() ?? 1
        return (oldStart, newStart)
    }

    // MARK: - Legacy AttributedString (backward compatibility)

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

// MARK: - Diff Line Row View

struct DiffLineRow: View {
    let line: DiffColorizer.DiffLine

    var body: some View {
        switch line.type {
        case .header:
            Text(line.content)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
        case .hunkHeader:
            Text(line.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.cyan)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.cyan.opacity(0.05))
        case .added, .removed, .context:
            HStack(spacing: 0) {
                // Old line number
                Text(line.oldLineNumber.map { String($0) } ?? "")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, alignment: .trailing)
                    .padding(.trailing, 4)

                // New line number
                Text(line.newLineNumber.map { String($0) } ?? "")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, alignment: .trailing)
                    .padding(.trailing, 4)

                // Gutter bar
                Rectangle()
                    .fill(gutterColor)
                    .frame(width: 3)
                    .padding(.vertical, 1)

                // Content
                Text(line.content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(contentColor)
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(backgroundColor)
        }
    }

    private var gutterColor: Color {
        switch line.type {
        case .added: .green
        case .removed: .red
        default: .clear
        }
    }

    private var contentColor: Color {
        switch line.type {
        case .added: .green
        case .removed: .red
        default: .primary
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .added: .green.opacity(0.08)
        case .removed: .red.opacity(0.08)
        default: .clear
        }
    }
}
