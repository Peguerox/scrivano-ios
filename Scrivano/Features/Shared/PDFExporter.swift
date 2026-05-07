import UIKit
import WebKit

final class PDFExporter {

    // MARK: - HTML → PDF

    /// Renders HTML in an off-screen WKWebView and exports a PDF using
    /// WKWebView.createPDF() — preserves all colors, backgrounds, and styling
    /// exactly as rendered on screen.
    static func makePDF(fromHTML html: String, title: String, completion: @escaping (URL?) -> Void) {
        DispatchQueue.main.async {
            let width: CGFloat = 595  // A4 width in points
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
            webView.isOpaque = false
            webView.backgroundColor = .white
            webView.scrollView.backgroundColor = .white
            let delegate = PDFDelegate(title: title, completion: completion)
            webView.navigationDelegate = delegate
            delegate.retain()
            webView.loadHTMLString(html, baseURL: nil)
            delegate.webView = webView
        }
    }

    // MARK: - Delegate

    private final class PDFDelegate: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        let title: String
        let completion: (URL?) -> Void
        private static var pool = Set<PDFDelegate>()

        init(title: String, completion: @escaping (URL?) -> Void) {
            self.title = title
            self.completion = completion
        }

        func retain()  { PDFDelegate.pool.insert(self) }
        func release() { PDFDelegate.pool.remove(self) }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Wait for JS markdown rendering to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.render(webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            completion(nil); release()
        }

        private func render(_ webView: WKWebView) {
            let config = WKPDFConfiguration()
            // No rect set → captures full scrollable content at actual rendered size
            webView.createPDF(configuration: config) { [weak self] result in
                guard let self else { return }
                defer { self.release() }
                switch result {
                case .success(let data):
                    let safe = self.title.replacingOccurrences(of: "/", with: "-")
                    let url  = FileManager.default.temporaryDirectory
                        .appendingPathComponent(safe)
                        .appendingPathExtension("pdf")
                    do {
                        try data.write(to: url)
                        DispatchQueue.main.async { self.completion(url) }
                    } catch {
                        DispatchQueue.main.async { self.completion(nil) }
                    }
                case .failure:
                    DispatchQueue.main.async { self.completion(nil) }
                }
            }
        }
    }
}
