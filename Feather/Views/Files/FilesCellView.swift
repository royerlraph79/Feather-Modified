//
//  FileCellView.swift
//  Feather
//
//  Created by David Wojcik III on 11/9/25.
//

import SwiftUI
import ImageIO

struct FileCell: View {
    let file: URL
    @State private var thumbnail: Image?
    @State private var folderDetails: String = "Folder"

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    thumbnail
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                }
            }
            .frame(width: 40, height: 40)
            .onAppear {
                loadThumbnail()
                if isDirectory { loadFolderDetails() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(file.lastPathComponent)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(fileType)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var isDirectory: Bool {
        (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private var fileType: String {
        if isDirectory {
            return folderDetails
        } else {
            let ext = file.pathExtension.uppercased()
            let size = formattedFileSize()
            let date = formattedCreationDate()
            
            // Build the subtitle: "EXT • SIZE • DATE"
            var components: [String] = [ext]
            if let size { components.append(size) }
            if let date { components.append(date) }
            
            return components.joined(separator: " • ")
        }
    }

    private func formattedFileSize() -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let bytes = attrs[.size] as? Int64 else {
            return nil
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formattedCreationDate() -> String? {
        guard let values = try? file.resourceValues(forKeys: [.creationDateKey]),
              let date = values.creationDate else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    private var icon: String {
        let ext = file.pathExtension.lowercased()
        switch ext {
        case "ipa": return "app.fill"
        case "dylib": return "puzzlepiece.extension.fill"
        case "deb": return "puzzlepiece.extension.fill"
        case "png", "jpg", "jpeg": return "photo.fill"
        default: return isDirectory ? "folder.fill" : "doc.fill"
        }
    }

    private func loadThumbnail() {
        let ext = file.pathExtension.lowercased()
        guard ext == "png" || ext == "jpg" || ext == "jpeg" else { return }
        if let ui = UIImage(contentsOfFile: file.path) {
            thumbnail = Image(uiImage: ui)
            return
        }
        if let src = CGImageSourceCreateWithURL(file as CFURL, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache as String: true] as CFDictionary) {
            thumbnail = Image(uiImage: UIImage(cgImage: cg))
        }
    }

    private func loadFolderDetails() {
        DispatchQueue.global(qos: .background).async {
            let count = (try? FileManager.default.contentsOfDirectory(atPath: file.path))?.count ?? 0
            let text = count == 0 ? "Folder • Empty" : "Folder • \(count) Item\(count > 1 ? "s" : "")"
            DispatchQueue.main.async { folderDetails = text }
        }
    }
}
