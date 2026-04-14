import Foundation

/// Converts a markdown string to an HTML body fragment.
/// Handles: headers, bold, italic, inline code, code blocks,
/// unordered/ordered lists, blockquotes, horizontal rules, links, strikethrough.
enum MarkdownConverter {

    static func toHTML(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html = ""
        var i = 0
        var inUL = false
        var inOL = false

        func closeList() {
            if inUL { html += "</ul>\n"; inUL = false }
            if inOL { html += "</ol>\n"; inOL = false }
        }

        while i < lines.count {
            let raw  = lines[i]
            let trim = raw.trimmingCharacters(in: .whitespaces)

            // ── Fenced code block ────────────────────────────────────────────
            if trim.hasPrefix("```") {
                closeList()
                let lang = String(trim.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                let escaped = code.joined(separator: "\n").htmlEscaped
                let cls = lang.isEmpty ? "" : " class=\"language-\(lang)\""
                html += "<pre><code\(cls)>\(escaped)</code></pre>\n"
                i += 1
                continue
            }

            // ── Horizontal rule ──────────────────────────────────────────────
            if trim == "---" || trim == "***" || trim == "___" {
                closeList()
                html += "<hr>\n"
                i += 1
                continue
            }

            // ── Headers ──────────────────────────────────────────────────────
            if trim.hasPrefix("#### ") {
                closeList()
                html += "<h4>\(inline(String(trim.dropFirst(5))))</h4>\n"
            } else if trim.hasPrefix("### ") {
                closeList()
                html += "<h3>\(inline(String(trim.dropFirst(4))))</h3>\n"
            } else if trim.hasPrefix("## ") {
                closeList()
                html += "<h2>\(inline(String(trim.dropFirst(3))))</h2>\n"
            } else if trim.hasPrefix("# ") {
                closeList()
                html += "<h1>\(inline(String(trim.dropFirst(2))))</h1>\n"
            }

            // ── Blockquote ───────────────────────────────────────────────────
            else if trim.hasPrefix("> ") {
                closeList()
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
                closeList()
                html += "<div class=\"gap\"></div>\n"
            }

            // ── Paragraph ────────────────────────────────────────────────────
            else {
                closeList()
                html += "<p>\(inline(trim))</p>\n"
            }

            i += 1
        }

        closeList()
        return html
    }

    // MARK: - Inline formatting

    private static func inline(_ text: String) -> String {
        var s = text.htmlEscaped

        // Inline code — apply first so inner chars aren't re-processed
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
