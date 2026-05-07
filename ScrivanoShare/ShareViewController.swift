import UIKit
import SwiftUI

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 3/255, green: 8/255, blue: 15/255, alpha: 1)
        extractFile()
    }

    private func extractFile() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else { cancel(); return }

        let candidates: [(String, Bool)] = [
            ("com.apple.m4a-audio",                                true),
            ("public.mp3",                                         true),
            ("com.microsoft.waveform-audio",                       true),
            ("public.audio",                                       true),
            ("com.adobe.pdf",                                      false),
            ("org.openxmlformats.wordprocessingml.document",       false),
            ("public.plain-text",                                  false),
            ("public.data",                                        false),
        ]

        for (typeId, isAudio) in candidates where provider.hasItemConformingToTypeIdentifier(typeId) {
            let suggestedName = provider.suggestedName

            provider.loadFileRepresentation(forTypeIdentifier: typeId) { [weak self] url, _ in
                guard let url else { DispatchQueue.main.async { self?.cancel() }; return }
                let ext = url.pathExtension.isEmpty ? (isAudio ? "m4a" : "pdf") : url.pathExtension

                // Use suggestedName if available; otherwise fall back to a clean generic name.
                // Never use url.lastPathComponent — it is always a UUID temp copy from the system.
                let originalName: String
                if let name = suggestedName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    originalName = name.hasSuffix(".\(ext)") ? name : "\(name).\(ext)"
                } else {
                    originalName = "imported_file.\(ext)"
                }

                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "." + ext)
                try? FileManager.default.copyItem(at: url, to: tmp)
                DispatchQueue.main.async { self?.show(fileURL: tmp, originalName: originalName, isAudio: isAudio) }
            }
            return
        }
        cancel()
    }

    private func show(fileURL: URL, originalName: String, isAudio: Bool) {
        let view = ShareView(
            fileURL: fileURL,
            originalName: originalName,
            isAudio: isAudio,
            onDone:   { [weak self] in self?.extensionContext?.completeRequest(returningItems: []) },
            onCancel: { [weak self] in self?.cancel() }
        )
        let host = UIHostingController(rootView: view)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        addChild(host)
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "com.scrivano.share", code: 0))
    }
}
