//
//  ImageViewerView.swift
//  Feather
//
//  Created by David Wojcik III on 11/9/25.
//

import SwiftUI
import QuickLook

struct ImageViewerView: UIViewControllerRepresentable {
    let imageURL: URL
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.delegate = context.coordinator

        let doneButton = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(context.coordinator.dismissViewer)
        )
        preview.navigationItem.rightBarButtonItem = doneButton
        preview.isEditing = false

        let nav = UINavigationController(rootViewController: preview)
        nav.navigationBar.prefersLargeTitles = false
        nav.navigationBar.tintColor = .systemBlue
        nav.modalPresentationStyle = .automatic
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(imageURL: imageURL, dismiss: dismiss) }

    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let imageURL: URL
        let dismiss: DismissAction

        init(imageURL: URL, dismiss: DismissAction) {
            self.imageURL = imageURL
            self.dismiss = dismiss
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            imageURL as NSURL
        }
        @objc func dismissViewer() { dismiss() }
        func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem)
        -> QLPreviewItemEditingMode { .disabled }
    }
}
