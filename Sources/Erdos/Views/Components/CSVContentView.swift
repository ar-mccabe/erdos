import SwiftUI
import WebKit

struct CSVContentView: View {
    let content: String

    var body: some View {
        CSVWebView(csv: content)
    }
}

// MARK: - WKWebView wrapper

struct CSVWebView: NSViewRepresentable {
    let csv: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        loadHTML(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadHTML(into: webView)
    }

    private func loadHTML(into webView: WKWebView) {
        let html = CSVHTMLBuilder.buildHTML(csv: csv)
        webView.loadHTMLString(html, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

// MARK: - CSV → HTML

enum CSVHTMLBuilder {

    static func buildHTML(csv: String) -> String {
        let rows = parseCSV(csv)

        guard !rows.isEmpty, rows.first?.isEmpty == false else {
            return wrapInPage("<p style='color:#888;'>Empty CSV file.</p>")
        }

        let maxDisplayRows = 1_000
        let headerRow = rows[0]
        let dataRows = Array(rows.dropFirst())
        let truncated = dataRows.count > maxDisplayRows
        let displayRows = truncated ? Array(dataRows.prefix(maxDisplayRows)) : dataRows
        let colCount = headerRow.count

        var summary = "\(dataRows.count) row\(dataRows.count == 1 ? "" : "s") × \(colCount) column\(colCount == 1 ? "" : "s")"
        if truncated {
            summary += " (showing first \(maxDisplayRows))"
        }

        var html = "<p style='color:#888; font-size:12px; margin:0 0 8px 0;'>\(summary)</p>"
        html += "<table><thead><tr>"
        for cell in headerRow {
            html += "<th>\(MarkdownWebViewHelper.escapeHTML(cell))</th>"
        }
        html += "</tr></thead><tbody>"

        for row in displayRows {
            html += "<tr>"
            // Pad or truncate to match header column count
            for i in 0..<colCount {
                let cell = i < row.count ? row[i] : ""
                html += "<td>\(MarkdownWebViewHelper.escapeHTML(cell))</td>"
            }
            html += "</tr>"
        }

        html += "</tbody></table>"

        if truncated {
            html += "<p style='color:#888; font-size:12px; margin:8px 0 0 0;'>⋯ \(dataRows.count - maxDisplayRows) more rows not shown.</p>"
        }

        return wrapInPage(html)
    }

    private static func wrapInPage(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        \(MarkdownWebViewHelper.css)
        td, th { white-space: nowrap; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - RFC 4180 CSV Parser

    /// Parses a CSV string into an array of rows, each row an array of field strings.
    /// Handles quoted fields (including embedded commas, quotes, and newlines).
    static func parseCSV(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        let chars = Array(csv.unicodeScalars)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            if inQuotes {
                if c == "\"" {
                    // Look ahead for escaped quote
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        continue
                    } else {
                        inQuotes = false
                        i += 1
                        continue
                    }
                } else {
                    currentField.unicodeScalars.append(c)
                    i += 1
                    continue
                }
            }

            // Not in quotes
            if c == "\"" {
                inQuotes = true
                i += 1
            } else if c == "," {
                currentRow.append(currentField)
                currentField = ""
                i += 1
            } else if c == "\r" {
                // Handle \r\n or bare \r
                currentRow.append(currentField)
                currentField = ""
                if !currentRow.allSatisfy({ $0.isEmpty }) || currentRow.count > 1 {
                    rows.append(currentRow)
                }
                currentRow = []
                i += 1
                if i < chars.count && chars[i] == "\n" {
                    i += 1
                }
            } else if c == "\n" {
                currentRow.append(currentField)
                currentField = ""
                if !currentRow.allSatisfy({ $0.isEmpty }) || currentRow.count > 1 {
                    rows.append(currentRow)
                }
                currentRow = []
                i += 1
            } else {
                currentField.unicodeScalars.append(c)
                i += 1
            }
        }

        // Flush last field/row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !currentRow.allSatisfy({ $0.isEmpty }) || currentRow.count > 1 {
                rows.append(currentRow)
            }
        }

        return rows
    }
}
