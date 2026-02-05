//
//  IconExtractor.swift
//  Feather
//

import UIKit
import Foundation

struct IconInfo: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let image: UIImage
    let extractedURL: URL?
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum IconExtractorError: Error {
    case appBundleNotFound
    case noIconsFound
    case extractionFailed(String)
}

class IconExtractor {
    static func extractIcons(from appBundleURL: URL, appFolderName: String) async throws -> [IconInfo] {
        let fileManager = FileManager.default
        
        // Verify the app bundle exists
        guard fileManager.fileExists(atPath: appBundleURL.path) else {
            throw IconExtractorError.appBundleNotFound
        }
        
        // Read Info.plist to find icon files
        let infoPlistURL = appBundleURL.appendingPathComponent("Info.plist")
        guard let infoPlist = NSDictionary(contentsOf: infoPlistURL) else {
            throw IconExtractorError.extractionFailed("Could not read Info.plist")
        }
        
        var iconFiles: [String] = []
        
        // Check for CFBundleIconFiles (legacy)
        if let iconFilesArray = infoPlist["CFBundleIconFiles"] as? [String] {
            iconFiles.append(contentsOf: iconFilesArray)
        }
        
        // Check for CFBundleIcons (modern)
        if let iconDict = infoPlist["CFBundleIcons"] as? [String: Any],
           let primaryIcon = iconDict["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFilesArray = primaryIcon["CFBundleIconFiles"] as? [String] {
            iconFiles.append(contentsOf: iconFilesArray)
        }
        
        // Also check CFBundleIconName
        if let iconName = infoPlist["CFBundleIconName"] as? String {
            iconFiles.append(iconName)
        }
        
        // Create extraction directory
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let extractedIconsDir = documentsDir
            .appendingPathComponent("ExtractedIcons")
            .appendingPathComponent(appFolderName)
        
        try? fileManager.createDirectory(at: extractedIconsDir, withIntermediateDirectories: true)
        
        var extractedIcons: [IconInfo] = []
        var processedFiles = Set<String>()
        
        // Function to try loading an icon
        func tryLoadIcon(name: String) {
            // Skip if already processed
            guard !processedFiles.contains(name) else { return }
            processedFiles.insert(name)
            
            // Try various extensions and scales
            let scales = ["@3x", "@2x", ""]
            let extensions = [".png", ""]
            
            for scale in scales {
                for ext in extensions {
                    let filename = name + scale + ext
                    let iconPath = appBundleURL.appendingPathComponent(filename)
                    
                    if fileManager.fileExists(atPath: iconPath.path),
                       let imageData = try? Data(contentsOf: iconPath),
                       let image = UIImage(data: imageData) {
                        
                        // Save to extraction directory
                        let destinationURL = extractedIconsDir.appendingPathComponent(filename)
                        try? imageData.write(to: destinationURL)
                        
                        let fileSize = (try? fileManager.attributesOfItem(atPath: iconPath.path)[.size] as? Int64) ?? 0
                        
                        let iconInfo = IconInfo(
                            name: filename,
                            size: fileSize,
                            image: image,
                            extractedURL: destinationURL
                        )
                        extractedIcons.append(iconInfo)
                    }
                }
            }
        }
        
        // Try loading all icon files from Info.plist
        for iconFile in iconFiles {
            tryLoadIcon(name: iconFile)
        }
        
        // Also try common icon names
        let commonNames = ["AppIcon", "Icon", "icon"]
        for name in commonNames {
            tryLoadIcon(name: name)
        }
        
        // If no icons found through Info.plist, scan the bundle for PNG files
        if extractedIcons.isEmpty {
            let contents = try? fileManager.contentsOfDirectory(at: appBundleURL, includingPropertiesForKeys: nil)
            let pngFiles = contents?.filter { $0.pathExtension.lowercased() == "png" } ?? []
            
            for pngURL in pngFiles {
                if let imageData = try? Data(contentsOf: pngURL),
                   let image = UIImage(data: imageData) {
                    
                    let filename = pngURL.lastPathComponent
                    let destinationURL = extractedIconsDir.appendingPathComponent(filename)
                    try? imageData.write(to: destinationURL)
                    
                    let fileSize = (try? fileManager.attributesOfItem(atPath: pngURL.path)[.size] as? Int64) ?? 0
                    
                    let iconInfo = IconInfo(
                        name: filename,
                        size: fileSize,
                        image: image,
                        extractedURL: destinationURL
                    )
                    extractedIcons.append(iconInfo)
                }
            }
        }
        
        guard !extractedIcons.isEmpty else {
            throw IconExtractorError.noIconsFound
        }
        
        // Sort by size (largest first)
        extractedIcons.sort { $0.size > $1.size }
        
        return extractedIcons
    }
}
