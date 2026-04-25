import UIKit

final class PDFExporter {

    static let pageWidth:  CGFloat = 595   // A4 width  in points
    static let pageHeight: CGFloat = 842   // A4 height in points

    /// Snapshots the full content of a UIScrollView (including off-screen content)
    /// and writes it to a paginated A4 PDF file, returning the file URL on success.
    static func makePDF(from scrollView: UIScrollView, title: String) -> URL? {
        guard let contentView = scrollView.subviews.first else { return nil }
        let contentSize = scrollView.contentSize
        guard contentSize.width > 1, contentSize.height > 1 else { return nil }

        // Render the full content to a UIImage at screen scale
        let imgRenderer = UIGraphicsImageRenderer(size: contentSize)
        let image = imgRenderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: contentSize))
            contentView.layer.render(in: ctx.cgContext)
        }

        // Scale factor to fit content width into A4 width
        let scale       = pageWidth / contentSize.width
        let scaledTotal = contentSize.height * scale
        let imgScale    = image.scale

        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let pdfData  = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, [
            kCGPDFContextTitle as String: title
        ])

        var yScaled: CGFloat = 0   // position in scaled (A4-width) coordinates
        while yScaled < scaledTotal {
            UIGraphicsBeginPDFPage()
            UIColor.white.setFill()
            UIRectFill(pageRect)

            // How many scaled points fit on this page
            let sliceScaledHeight = min(pageHeight, scaledTotal - yScaled)

            // Corresponding source rect in the original (unscaled) image pixels
            let srcY      = (yScaled  / scale) * imgScale
            let srcHeight = (sliceScaledHeight / scale) * imgScale
            let srcWidth  = contentSize.width * imgScale

            if let cgFull = image.cgImage,
               let cgSlice = cgFull.cropping(to: CGRect(
                   x: 0, y: srcY,
                   width: srcWidth, height: srcHeight
               )) {
                let sliceImg = UIImage(cgImage: cgSlice,
                                       scale: imgScale,
                                       orientation: image.imageOrientation)
                sliceImg.draw(in: CGRect(x: 0, y: 0,
                                         width: pageWidth,
                                         height: sliceScaledHeight))
            }

            yScaled += pageHeight
        }

        UIGraphicsEndPDFContext()

        let safe = title.replacingOccurrences(of: "/", with: "-")
        let url  = FileManager.default.temporaryDirectory
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
