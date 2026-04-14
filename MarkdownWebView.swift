import SwiftUI
import WebKit

struct MarkdownWebView: UIViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.isOpaque = false
        // Match app background so there's no white flash
        let bg = UIColor(red: 0.024, green: 0.055, blue: 0.118, alpha: 1) // #060e1e
        wv.backgroundColor = bg
        wv.scrollView.backgroundColor = bg
        wv.scrollView.showsVerticalScrollIndicator = false
        wv.scrollView.contentInset = .zero
        wv.navigationDelegate = context.coordinator
        wv.loadHTMLString(buildHTML(markdown), baseURL: nil)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        guard context.coordinator.lastMarkdown != markdown else { return }
        context.coordinator.lastMarkdown = markdown
        wv.loadHTMLString(buildHTML(markdown), baseURL: nil)
    }

    // MARK: - HTML assembly

    private func buildHTML(_ md: String) -> String {
        let body = MarkdownConverter.toHTML(md)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }

        body {
            background: #060e1e;
            color: rgba(255,255,255,0.87);
            font-family: -apple-system, 'SF Pro Text', sans-serif;
            font-size: 15px;
            line-height: 1.75;
            padding: 18px 20px 36px 20px;
            -webkit-text-size-adjust: none;
        }

        .gap { height: 0.55em; }

        /* ── Headings ── */
        h1, h2, h3, h4 {
            color: #ffffff;
            font-weight: 800;
            margin-top: 1.3em;
            margin-bottom: 0.35em;
            line-height: 1.2;
        }
        h1 { font-size: 1.75em; }
        h2 { font-size: 1.35em; border-bottom: 1px solid rgba(59,130,246,0.25); padding-bottom: 0.3em; }
        h3 { font-size: 1.1em; color: rgba(255,255,255,0.9); }
        h4 { font-size: 0.97em; color: rgba(255,255,255,0.75); font-weight: 700; }

        /* ── Paragraphs ── */
        p { margin: 0.5em 0; }

        /* ── Inline styles ── */
        strong { color: #ffffff; font-weight: 700; }
        em     { color: rgba(255,255,255,0.75); font-style: italic; }
        del    { color: rgba(255,255,255,0.38); }

        /* ── Inline code ── */
        code {
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 0.86em;
            background: rgba(34,211,238,0.10);
            color: #22d3ee;
            padding: 2px 6px;
            border-radius: 5px;
        }

        /* ── Code block ── */
        pre {
            background: #070f1e;
            border: 1px solid rgba(59,130,246,0.28);
            border-radius: 12px;
            padding: 14px 16px;
            overflow-x: auto;
            margin: 0.9em 0;
        }
        pre code {
            background: none;
            color: rgba(255,255,255,0.82);
            padding: 0;
            font-size: 0.84em;
            line-height: 1.65;
        }

        /* ── Blockquote ── */
        blockquote {
            border-left: 3px solid #22d3ee;
            margin: 0.7em 0;
            padding: 7px 14px;
            background: rgba(34,211,238,0.06);
            border-radius: 0 10px 10px 0;
            color: rgba(255,255,255,0.6);
            font-style: italic;
        }

        /* ── Lists ── */
        ul, ol { padding-left: 1.5em; margin: 0.5em 0; }
        li { margin: 0.28em 0; }
        li::marker { color: #22d3ee; }

        /* ── Horizontal rule ── */
        hr {
            border: none;
            border-top: 1px solid rgba(255,255,255,0.1);
            margin: 1.1em 0;
        }

        /* ── Links ── */
        a { color: #22d3ee; text-decoration: none; }
        a:active { opacity: 0.7; }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastMarkdown: String = ""

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated,
               let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
