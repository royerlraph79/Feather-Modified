//
//  DocumentImporter.swift
//  Feather
//
//  Created by David Wojcik III on 11/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

extension URL: Identifiable {
    public var id: String { path }
}

struct DocumentImporter: UIViewControllerRepresentable {
    // UPDATED: Default to [.item] to allow any file type
    var allowedTypes: [UTType] = [.item]
    var onImport: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImport: onImport)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onImport: (URL) -> Void
        init(onImport: @escaping (URL) -> Void) { self.onImport = onImport }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onImport(url)
        }
    }
}
