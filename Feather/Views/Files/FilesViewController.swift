//
//  FilesViewController.swift
//  Feather
//
//  Created by David Wojcik III on 11/3/25.
//

import UIKit
import UniformTypeIdentifiers
import Zip

class FilesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    
    private var tableView: UITableView!
    private var files: [URL] = []
    private var filesURL: URL!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Files"
        view.backgroundColor = .systemBackground
        
        // Use a clean directory under Documents/Feather/Files
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        filesURL = documentsURL.appendingPathComponent("Feather/Files", isDirectory: true)
        try? FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        
        // Table setup
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.delegate = self
        tableView.dataSource = self
        view.addSubview(tableView)
        
        // Import button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(importFile)
        )
        
        loadFiles()
    }
    
    // MARK: - Load Files
    func loadFiles() {
        do {
            files = try FileManager.default.contentsOfDirectory(at: filesURL, includingPropertiesForKeys: nil)
        } catch {
            print("Error loading files:", error)
            files = []
        }
        tableView.reloadData()
    }
    
    // MARK: - Import
    @objc func importFile() {
        // UPDATED: Allow any file type
        let supportedTypes: [UTType] = [.item]
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let root = window.rootViewController {
            root.present(picker, animated: true)
        } else {
            present(picker, animated: true)
        }
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let pickedURL = urls.first else { return }
        let accessGranted = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessGranted { pickedURL.stopAccessingSecurityScopedResource() } }
        
        do {
            let destinationURL = filesURL.appendingPathComponent(pickedURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: pickedURL, to: destinationURL)
            
            // Automatically unzip IPA files
            if destinationURL.pathExtension.lowercased() == "ipa" {
                do {
                    let unzipDestination = filesURL.appendingPathComponent(destinationURL.deletingPathExtension().lastPathComponent)
                    try self.unzipItem(at: destinationURL, to: unzipDestination)
                } catch {
                    print("Unzip failed:", error)
                }
            }
            
            loadFiles()
            showAlert(title: "Imported", message: pickedURL.lastPathComponent)
        } catch {
            showAlert(title: "Error", message: error.localizedDescription)
        }
    }
    
    // MARK: - TableView
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return files.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let fileURL = files[indexPath.row]
        cell.textLabel?.text = fileURL.lastPathComponent
        let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        cell.detailTextLabel?.text = isDir ? "Folder" : fileURL.pathExtension.uppercased()
        cell.accessoryType = isDir ? .disclosureIndicator : .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let fileURL = files[indexPath.row]
        let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        
        if fileURL.pathExtension.lowercased() == "ipa" && !isDir {
            showIPAPrompt(for: fileURL)
        } else if fileURL.lastPathComponent == "Payload" {
            showPayloadPrompt(for: fileURL)
        } else if isDir {
            showFolderContents(at: fileURL)
        } else {
            print("Tapped file:", fileURL.path)
        }
    }
    
    // MARK: - IPA / Payload Handling
    private func showIPAPrompt(for ipaURL: URL) {
        let ac = UIAlertController(title: ipaURL.lastPathComponent, message: nil, preferredStyle: .actionSheet)
        ac.addAction(UIAlertAction(title: "Unzip IPA", style: .default) { _ in
            do {
                let dest = self.filesURL.appendingPathComponent(ipaURL.deletingPathExtension().lastPathComponent)
                try self.unzipItem(at: ipaURL, to: dest)
                self.loadFiles()
            } catch {
                self.showAlert(title: "Error", message: "Unzip failed: \(error.localizedDescription)")
            }
        })
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(ac, animated: true)
    }
    
    private func showPayloadPrompt(for payloadURL: URL) {
        let ac = UIAlertController(title: "Payload Folder", message: nil, preferredStyle: .actionSheet)
        ac.addAction(UIAlertAction(title: "View Contents", style: .default) { _ in
            self.showFolderContents(at: payloadURL)
        })
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(ac, animated: true)
    }
    
    // MARK: - Helper Functions (moved here instead of extension)
    private func unzipItem(at sourceURL: URL, to destinationURL: URL) throws {
        // Make sure destination exists
        try? FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // Copy to temporary .zip (Zip.swift requires .zip extension)
        let tempZip = sourceURL.deletingPathExtension().appendingPathExtension("zip")
        if FileManager.default.fileExists(atPath: tempZip.path) {
            try? FileManager.default.removeItem(at: tempZip)
        }
        try FileManager.default.copyItem(at: sourceURL, to: tempZip)

        // Give iOS a moment to flush the copy before reading
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        // Try unzipping
        do {
            try Zip.unzipFile(tempZip, destination: destinationURL, overwrite: true, password: nil)
            try? FileManager.default.removeItem(at: tempZip)
            print("Successfully unzipped:", destinationURL.path)
        } catch {
            print("Unzip failed:", error)
            throw error
        }
    }
    
    private func zipItem(at sourceURL: URL, to destinationURL: URL, shouldKeepParent: Bool = true) throws {
        if shouldKeepParent {
            try Zip.zipFiles(paths: [sourceURL], zipFilePath: destinationURL, password: nil, progress: nil)
        } else {
            let contents = try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
            try Zip.zipFiles(paths: contents, zipFilePath: destinationURL, password: nil, progress: nil)
        }
    }
    
    private func showFolderContents(at folderURL: URL) {
        let contentsVC = FolderContentsViewController(folderURL: folderURL)
        navigationController?.pushViewController(contentsVC, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
    }
}
