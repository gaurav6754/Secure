import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Native UIKit UIDocumentPickerViewController wrapper using `asCopy: true`.
/// Fixes the iPadOS SwiftUI `.fileImporter` bug where PDFs in Recents / On My iPad / iCloud
/// appear unselectable or fail security-scoped reads.
struct DocumentPickerSheet: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
