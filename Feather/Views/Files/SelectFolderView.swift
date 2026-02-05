//
//  SelectFolderView.swift
//  Feather
//
//  Created by David Wojcik III on 11/9/25.
//

import SwiftUI

struct SelectFolderView: View {
    let root: URL
    let onSelect: (URL) -> Void

    @State private var folders: [URL] = []
    @State private var current: URL
    @Environment(\.dismiss) private var dismiss

    init(root: URL, onSelect: @escaping (URL) -> Void) {
        self.root = root
        self.onSelect = onSelect
        _current = State(initialValue: root)
    }

    var body: some View {
        NavigationStack {
            List(folders, id: \.self) { folder in
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                    Text(folder.lastPathComponent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // Navigate deeper into this folder
                    current = folder
                    loadFolders()
                }
            }
            .navigationTitle(current == root ? "Select Folder" : current.lastPathComponent)
            .toolbar {
                // Cancel button (top-left)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        if current != root {
                            current = current.deletingLastPathComponent()
                            loadFolders()
                        } else {
                            dismiss()
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select") {
                        onSelect(current)
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                // Fix: Ensure folders load the first time
                DispatchQueue.main.async {
                    loadFolders()
                }
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                loadFolders()
            }
        }
        .onChange(of: current) { _ in
            DispatchQueue.main.async {
                loadFolders()
            }
        }
    }

    // MARK: - Load folders in the current directory
    private func loadFolders() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: current,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        folders = contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() })
    }
}
