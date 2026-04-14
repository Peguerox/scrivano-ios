import WebKit
import UIKit

enum PDFExporter {
    private static var webView: WKWebView?

    static func export(markdownHTML: String, title: String) {
        let html = """
        <!DOCTYPE html><html><head><meta charset="UTF-8">
        <style>
        body{font-family:-apple-system,'Helvetica Neue',sans-serif;font-size:15px;line-height:1.7;color:#1a1a1a;padding:36px 44px;background:#fff}
        h1{font-size:1.9em;font-weight:800;border-bottom:2px solid #e5e7eb;padding-bottom:.3em;margin:1.3em 0 .4em}
        h2{font-size:1.45em;font-weight:700;border-bottom:1px solid #e5e7eb;padding-bottom:.25em;margin:1.2em 0 .35em}
        h3{font-size:1.15em;font-weight:700;margin:1em 0 .3em}
        h4{font-size:1em;font-weight:700;color:#444;margin:.9em 0 .25em}
        p{margin:.55em 0}strong{font-weight:700}em{font-style:italic}del{text-decoration:line-through;color:#888}
        code{font-family:'SF Mono',Menlo,monospace;font-size:.85em;background:#f3f4f6;color:#0070c0;padding:2px 5px;border-radius:4px}
        pre{background:#f8f9fa;border:1px solid #e5e7eb;border-radius:7px;padding:14px 16px;margin:.9em 0}
        pre code{background:none;color:#374151;padding:0}
        blockquote{border-left:4px solid #3b82f6;margin:.9em 0;padding:8px 16px;background:#eff6ff;color:#374151}
        ul,ol{padding-left:1.6em;margin:.5em 0}li{margin:.28em 0}
        table{width:100%;border-collapse:collapse;margin:.9em 0}
        th,td{padding:9px 13px;border:1px solid #e5e7eb;text-align:left}
        th{background:#f0f4f8;font-weight:700}
        tr:nth-child(even) td{background:#f9fafb}
        img{max-width:100%;border-radius:7px;margin:.5em 0;display:block}
        hr{border:none;border-top:1px solid #e5e7eb;margin:1.4em 0}
        a{color:#2563eb}
        </style></head><body>\(markdownHTML)</body></html>
        """
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
        webView = wv
        wv.loadHTMLString(html, baseURL: nil)
        let safeTitle = title.replacingOccurrences(of: "/", with: "-")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            wv.createPDF { result in
                webView = nil
                guard case .success(let data) = result else { return }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(safeTitle).appendingPathExtension("pdf")
                try? data.write(to: url)
                DispatchQueue.main.async {
                    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let root = scene.windows.first?.rootViewController else { return }
                    let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    root.present(vc, animated: true)
                }
            }
        }
    }
}
