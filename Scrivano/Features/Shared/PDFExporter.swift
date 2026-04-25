import UIKit
import WebKit

final class PDFExporter {

    // MARK: - HTML → paginated PDF (primary path)

    /// Renders HTML in an off-screen WKWebView and exports a proper A4 PDF
    /// using UIPrintPageRenderer — supports real pagination, images, tables, fonts.
    static func makePDF(fromHTML html: String, title: String, completion: @escaping (URL?) -> Void) {
        DispatchQueue.main.async {
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842))
            webView.isOpaque = false
            webView.backgroundColor = .white
            let delegate = PrintDelegate(title: title, completion: completion)
            webView.navigationDelegate = delegate
            delegate.retain()                          // keep alive until done
            webView.loadHTMLString(html, baseURL: nil)
            delegate.webView = webView                 // prevent dealloc
        }
    }

    // MARK: - Print delegate

    private final class PrintDelegate: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        let title: String
        let completion: (URL?) -> Void
        private static var pool = Set<PrintDelegate>()

        init(title: String, completion: @escaping (URL?) -> Void) {
            self.title = title
            self.completion = completion
        }

        func retain()  { PrintDelegate.pool.insert(self) }
        func release() { PrintDelegate.pool.remove(self) }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Small delay to let JS finish rendering the markdown
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.render(webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            completion(nil); release()
        }

        private func render(_ webView: WKWebView) {
            let paperRect   = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4
            let printRect   = CGRect(x: 28, y: 28, width: 539, height: 786) // ~10mm margins

            let renderer = UIPrintPageRenderer()
            renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
            renderer.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
            renderer.setValue(NSValue(cgRect: printRect), forKey: "printableRect")

            let pdfData = NSMutableData()
            UIGraphicsBeginPDFContextToData(pdfData, paperRect, [
                kCGPDFContextTitle as String: title
            ])
            renderer.prepare(forDrawingPages: NSMakeRange(0, renderer.numberOfPages))
            let bounds = UIGraphicsGetPDFContextBounds()
            for i in 0 ..< renderer.numberOfPages {
                UIGraphicsBeginPDFPage()
                renderer.drawPage(at: i, in: bounds)
            }
            UIGraphicsEndPDFContext()

            let safe = title.replacingOccurrences(of: "/", with: "-")
            let url  = FileManager.default.temporaryDirectory
                .appendingPathComponent(safe)
                .appendingPathExtension("pdf")
            do {
                try pdfData.write(to: url)
                DispatchQueue.main.async { self.completion(url) }
            } catch {
                print("[PDFExporter] write error: \(error)")
                DispatchQueue.main.async { self.completion(nil) }
            }
            release()
        }
    }
}
