import UIKit

final class PDFExporter {

    /// Snapshots the full content of a UIScrollView (including off-screen content)
    /// and writes it to a PDF file, returning the file URL on success.
    static func makePDF(from scrollView: UIScrollView, title: String) -> URL? {
        guard let contentView = scrollView.subviews.first else { return nil }
        let contentSize = scrollView.contentSize
        guard contentSize.width > 1, contentSize.height > 1 else { return nil }

        // Render the full content layer (sublayers included) to a UIImage
        let imgRenderer = UIGraphicsImageRenderer(size: contentSize)
        let image = imgRenderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: contentSize))
            contentView.layer.render(in: ctx.cgContext)
        }

        // Fit content into A4-width page (595pt)
        let pageWidth: CGFloat = 595
        let scale = pageWidth / contentSize.width
        let pageHeight = contentSize.height * scale

        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        UIGraphicsBeginPDFPage()
        UIColor.white.setFill()
        UIRectFill(pageRect)
        image.draw(in: pageRect)
        UIGraphicsEndPDFContext()

        let safe = title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safe)
            .appendingPathExtension("pdf")
        do {
            try pdfData.write(to: url)
            return url
        } catch {
            print("[PDFExporter] write error: \(error)")
            return nil
        }
    }
}
