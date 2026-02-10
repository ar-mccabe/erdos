import SwiftUI
import WebKit

struct MarkdownContentView: View {
    let content: String

    var body: some View {
        MarkdownWebView(markdown: content)
    }
}

// MARK: - WKWebView wrapper for rendered markdown

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadHTML(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadHTML(into: webView)
    }

    private func loadHTML(into webView: WKWebView) {
        let html = Self.buildHTML(markdown: markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - Markdown to HTML

    static func buildHTML(markdown: String) -> String {
        let body = markdownToHTML(markdown)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        \(css)
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static func markdownToHTML(_ md: String) -> String {
        let lines = md.components(separatedBy: "\n")
        var html: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code blocks
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code.append(escapeHTML(lines[i]))
                    i += 1
                }
                let langAttr = lang.isEmpty ? "" : " class=\"language-\(lang)\""
                html.append("<pre><code\(langAttr)>\(code.joined(separator: "\n"))</code></pre>")
                i += 1
                continue
            }

            // Headers
            if line.hasPrefix("######") {
                html.append("<h6>\(inlineMarkdown(String(line.dropFirst(6).drop(while: { $0 == " " }))))</h6>")
            } else if line.hasPrefix("#####") {
                html.append("<h5>\(inlineMarkdown(String(line.dropFirst(5).drop(while: { $0 == " " }))))</h5>")
            } else if line.hasPrefix("####") {
                html.append("<h4>\(inlineMarkdown(String(line.dropFirst(4).drop(while: { $0 == " " }))))</h4>")
            } else if line.hasPrefix("###") {
                html.append("<h3>\(inlineMarkdown(String(line.dropFirst(3).drop(while: { $0 == " " }))))</h3>")
            } else if line.hasPrefix("##") {
                html.append("<h2>\(inlineMarkdown(String(line.dropFirst(2).drop(while: { $0 == " " }))))</h2>")
            } else if line.hasPrefix("#") {
                html.append("<h1>\(inlineMarkdown(String(line.dropFirst(1).drop(while: { $0 == " " }))))</h1>")
            }
            // Horizontal rule
            else if line.trimmingCharacters(in: .whitespaces).matches(of: /^[-*_]{3,}$/).count > 0 {
                html.append("<hr>")
            }
            // Tables
            else if line.contains("|") && line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                var rows: [String] = []
                while i < lines.count && lines[i].contains("|") {
                    rows.append(lines[i])
                    i += 1
                }
                html.append(parseTable(rows))
                continue
            }
            // Unordered list items
            else if line.matches(of: /^(\s*)[*+-]\s+(.*)/).first != nil {
                var items: [String] = []
                while i < lines.count {
                    if let m = lines[i].matches(of: /^(\s*)[*+-]\s+(.*)/).first {
                        items.append("<li>\(inlineMarkdown(String(m.output.2)))</li>")
                    } else if lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        break
                    } else {
                        break
                    }
                    i += 1
                }
                html.append("<ul>\(items.joined())</ul>")
                continue
            }
            // Ordered list items
            else if line.matches(of: /^(\s*)\d+[.)]\s+(.*)/).first != nil {
                var items: [String] = []
                while i < lines.count {
                    if let m = lines[i].matches(of: /^(\s*)\d+[.)]\s+(.*)/).first {
                        items.append("<li>\(inlineMarkdown(String(m.output.2)))</li>")
                    } else if lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        break
                    } else {
                        break
                    }
                    i += 1
                }
                html.append("<ol>\(items.joined())</ol>")
                continue
            }
            // Blockquote
            else if line.hasPrefix(">") {
                let content = String(line.dropFirst(1).drop(while: { $0 == " " }))
                html.append("<blockquote>\(inlineMarkdown(content))</blockquote>")
            }
            // Blank line
            else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // skip
            }
            // Paragraph
            else {
                html.append("<p>\(inlineMarkdown(line))</p>")
            }

            i += 1
        }

        return html.joined(separator: "\n")
    }

    static func inlineMarkdown(_ text: String) -> String {
        var s = escapeHTML(text)

        // Bold + italic
        s = s.replacing(/\*\*\*(.+?)\*\*\*/) { "<strong><em>\($0.output.1)</em></strong>" }
        // Bold
        s = s.replacing(/\*\*(.+?)\*\*/) { "<strong>\($0.output.1)</strong>" }
        // Italic
        s = s.replacing(/\*(.+?)\*/) { "<em>\($0.output.1)</em>" }
        // Inline code
        s = s.replacing(/`([^`]+)`/) { "<code>\($0.output.1)</code>" }
        // Links
        s = s.replacing(/\[([^\]]+)\]\(([^)]+)\)/) { "<a href=\"\($0.output.2)\">\($0.output.1)</a>" }
        // Strikethrough
        s = s.replacing(/~~(.+?)~~/) { "<del>\($0.output.1)</del>" }

        return s
    }

    static func parseTable(_ rows: [String]) -> String {
        func splitCells(_ row: String) -> [String] {
            let parts = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            // Drop leading/trailing empties from "|col|col|"
            let trimmed = parts.count >= 2 ? Array(parts[1..<(parts.count - 1)]) : parts
            return trimmed
        }

        guard rows.count >= 2 else { return rows.map { escapeHTML($0) }.joined() }

        let headerCells = splitCells(rows[0])
        // Row 1 is the separator (|---|---|), skip it
        let isSeparator = { (row: String) -> Bool in
            row.replacing(/[|\s:-]/, with: { _ in "" }).isEmpty
        }

        var html = "<table><thead><tr>"
        for cell in headerCells {
            html += "<th>\(inlineMarkdown(cell))</th>"
        }
        html += "</tr></thead><tbody>"

        for row in rows.dropFirst() {
            if isSeparator(row) { continue }
            let cells = splitCells(row)
            html += "<tr>"
            for cell in cells {
                html += "<td>\(inlineMarkdown(cell))</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"
        return html
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - CSS

    static let css = """
    :root {
        color-scheme: dark;
    }
    body {
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        font-size: 13px;
        line-height: 1.6;
        color: #e0e0e0;
        padding: 16px 20px;
        margin: 0;
        -webkit-user-select: text;
    }
    h1 { font-size: 1.6em; font-weight: 700; margin: 0.8em 0 0.4em; color: #ffffff; }
    h2 { font-size: 1.3em; font-weight: 600; margin: 0.8em 0 0.4em; color: #f0f0f0; }
    h3 { font-size: 1.1em; font-weight: 600; margin: 0.6em 0 0.3em; color: #e8e8e8; }
    h4, h5, h6 { font-size: 1em; font-weight: 600; margin: 0.5em 0 0.3em; color: #e0e0e0; }
    h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
    p { margin: 0.5em 0; }
    ul, ol { margin: 0.4em 0; padding-left: 1.5em; }
    li { margin: 0.2em 0; }
    code {
        font-family: "SF Mono", Menlo, monospace;
        font-size: 0.9em;
        background: rgba(255,255,255,0.08);
        padding: 0.15em 0.4em;
        border-radius: 4px;
    }
    pre {
        background: rgba(255,255,255,0.06);
        border-radius: 6px;
        padding: 12px 14px;
        overflow-x: auto;
        margin: 0.6em 0;
    }
    pre code {
        background: none;
        padding: 0;
        font-size: 0.85em;
        line-height: 1.5;
    }
    blockquote {
        border-left: 3px solid rgba(255,255,255,0.15);
        margin: 0.5em 0;
        padding: 0.2em 0 0.2em 1em;
        color: #a0a0a0;
    }
    hr {
        border: none;
        border-top: 1px solid rgba(255,255,255,0.1);
        margin: 1em 0;
    }
    table {
        border-collapse: collapse;
        margin: 0.6em 0;
        width: 100%;
        font-size: 0.95em;
    }
    th, td {
        border: 1px solid rgba(255,255,255,0.1);
        padding: 6px 10px;
        text-align: left;
    }
    th {
        background: rgba(255,255,255,0.06);
        font-weight: 600;
        color: #f0f0f0;
    }
    tr:nth-child(even) td {
        background: rgba(255,255,255,0.02);
    }
    a { color: #6cb4ee; text-decoration: none; }
    a:hover { text-decoration: underline; }
    strong { color: #f0f0f0; }
    del { color: #888; }
    """
}
