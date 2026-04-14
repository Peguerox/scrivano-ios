import Foundation

/// Converts a markdown string to an HTML body fragment.
/// Handles: headers, bold, italic, inline code, code blocks,
/// unordered/ordered lists, blockquotes, horizontal rules, links,
/// strikethrough, GFM tables, images.
enum MarkdownConverter {

    static func toHTML(_ markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var html = ""
        var i = 0
        var inUL = false
        var inOL = false

        while i < lines.count {
            let raw  = lines[i]
            let trim = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            // ── Fenced code block ────────────────────────────────────────────
            if trim.hasPrefix("```") {
                if inUL { html += "</ul>\n"; inUL = false }
                if inOL { html += "</ol>\n"; inOL = false }
                let lang = String(trim.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                let escaped = code.joined(separator: "\n").htmlEscaped
                let cls = lang.isEmpty ? "" : " class=\"language-\(lang)\""
                html += "<pre><code\(cls)>\(escaped)</code></pre>\n"
                i += 1
                continue
            }

            // ── GFM Table ────────────────────────────────────────────────────
            if trim.contains("|") && i + 1 < lines.count && isSeparatorRow(lines[i + 1]) {
                if inUL { html += "</ul>\n"; inUL = false }
                if inOL { html += "</ol>\n"; inOL = false }
                let headers = splitTableRow(trim)
                i += 2
                html += "<div class=\"table-wrap\"><table><thead><tr>"
                for h in headers {
                    html += "<th>\(inline(h))</th>"
                }
                html += "</tr></thead><tbody>\n"
                while i < lines.count {
                    let r = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !r.isEmpty && r.contains("|") else { break }
                    let cells = splitTableRow(r)
                    html += "<tr>"
                    for j in 0..<headers.count {
                        let cell = j < cells.count ? cells[j] : ""
                        html += "<td>\(inline(cell))</td>"
                    }
                    html += "</tr>\n"
                    i += 1
                }
                html += "</tbody></table></div>\n"
                continue
            }

            // ── Horizontal rule ──────────────────────────────────────────────
            if trim == "---" || trim == "***" || trim == "___" {
                if inUL { html += "</ul>\n"; inUL = false }
                if inOL { html += "</ol>\n"; inOL = false }
                html += "<hr>\n"
                i += 1
                continue
            }

            // ── Headers ──────────────────────────────────────────────────────
            if trim.hasPrefix("#### ") {
                if inUL { html += "</ul>\n"; inUL = false }
                if inOL { html += "</ol>\n"; inOL = false }
                html += "<h4>\(inline(String(trim.dropFirst(5))))</h4>\n"
            } else if trim.hasPrefix("### ") {
                if inUL { html += "</ul>\n"; inUL = false }
                if inOL { html += "</ol>\n"; inOL = false }
                html += "<h3>\(inline(String(trim.dropFirst(4))))</h3>\n"
            } else if trim.hasPrefix("## ") {
                if inUL { html += "</ul>\n"; inUL = false }
                if inOL { html += "</ol>\n"; inOL = false }
                html += "<h2>\(inline(String(trim.dropFirst(3))))</h2>\n"
            } else if trim.hasPrefix("# ") {
                if inUL { html += "</ul>\n"; inUL = false }
                if inOL { html += "</ol>\n"; inOL = false }
                html += "<h1>\(inline(String(trim.dropFirst(2))))</h1>\n"
            }

            // ── Blockquote ───────────────────────────────────────────────────
            else if trim.hasPrefix("> ") {
                if inUL { html += "</ul>\n"; inUL = false }
                if inOL { html += "</ol>\n"; inOL = false }
                html += "<blockquote>\(inline(String(trim.dropFirst(2))))</blockquote>\n"
            }

            // ── Unordered list ───────────────────────────────────────────────
            else if trim.hasPrefix("- ") || trim.hasPrefix("* ") || trim.hasPrefix("+ ") {
                if inOL { html += "</ol>\n"; inOL = false }
                if !inUL { html += "<ul>\n"; inUL = true }
                html += "<li>\(inline(String(trim.dropFirst(2))))</li>\n"
            }

            // ── Ordered list ─────────────────────────────────────────────────
            else if trim.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                if inUL { html += "</ul>\n"; inUL = false }
                if !inOL { html += "<ol>\n"; inOL = true }
                let content = trim.replacingOccurrences(of: #"^\d+\. "#, with: "", options: .regularExpression)
                html += "<li>\(inline(content))</li>\n"
            }

            // ── Empty line ───────────────────────────────────────────────────
            else if trim.isEmpty {
                if inUL { html += "</ul>\n"; inUL = false }
                if inOL { html += "</ol>\n"; inOL = false }
                html += "<div class=\"gap\"></div>\n"
            }

            // ── Paragraph ────────────────────────────────────────────────────
            else {
                if inUL { html += "</ul>\n"; inUL = false }
                if inOL { html += "</ol>\n"; inOL = false }
                html += "<p>\(inline(trim))</p>\n"
            }

            i += 1
        }

        if inUL { html += "</ul>\n" }
        if inOL { html += "</ol>\n" }
        return html
    }

    // MARK: - Table helpers

    /// Returns true if the line is a GFM separator row like `| --- | :---: | ---: |`
    /// A separator row contains only `|`, `-`, `:`, spaces, and tabs — no letters or digits.
    private static func isSeparatorRow(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.contains("|"), s.contains("-") else { return false }
        return !s.contains(where: { $0 != "|" && $0 != "-" && $0 != ":" && $0 != " " && $0 != "\t" })
    }

    /// Splits `| A | B | C |` into `["A", "B", "C"]`
    private static func splitTableRow(_ s: String) -> [String] {
        var r = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.hasPrefix("|") { r = String(r.dropFirst()) }
        if r.hasSuffix("|") { r = String(r.dropLast()) }
        return r.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    // MARK: - Inline formatting

    private static func inline(_ text: String) -> String {
        var s = text.htmlEscaped

        // Images — before links so ![...](url) isn't eaten by link regex
        s = s.replacingOccurrences(of: #"!\[([^\]]*)\]\(([^\)]+)\)"#,
                                   with: "<img src=\"$2\" alt=\"$1\">",
                                   options: .regularExpression)
        // Inline code — before other inline so inner content isn't re-processed
        s = s.replacingOccurrences(of: #"`([^`]+)`"#,
                                   with: "<code>$1</code>",
                                   options: .regularExpression)
        // Bold + italic
        s = s.replacingOccurrences(of: #"\*\*\*(.+?)\*\*\*"#,
                                   with: "<strong><em>$1</em></strong>",
                                   options: .regularExpression)
        // Bold
        s = s.replacingOccurrences(of: #"\*\*(.+?)\*\*"#,
                                   with: "<strong>$1</strong>",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: #"__(.+?)__"#,
                                   with: "<strong>$1</strong>",
                                   options: .regularExpression)
        // Italic
        s = s.replacingOccurrences(of: #"\*(.+?)\*"#,
                                   with: "<em>$1</em>",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: #"_(.+?)_"#,
                                   with: "<em>$1</em>",
                                   options: .regularExpression)
        // Strikethrough
        s = s.replacingOccurrences(of: #"~~(.+?)~~"#,
                                   with: "<del>$1</del>",
                                   options: .regularExpression)
        // Links
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\(([^\)]+)\)"#,
                                   with: "<a href=\"$2\">$1</a>",
                                   options: .regularExpression)
        return s
    }
}

// MARK: - String helper

private extension String {
    var htmlEscaped: String {
        self
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
