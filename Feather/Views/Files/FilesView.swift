//
//  FilesView.swift
//  Feather
//
//  Created by David Wojcik III on 11/3/25.
//

import SwiftUI
import UniformTypeIdentifiers
import NimbleViews
import Zip
import ImageIO
import QuickLook

// MARK: - Sorting Options
enum SortOption: String, CaseIterable {
    case name = "Name"
    case type = "File Type"
    case size = "Size"
    case modified = "Date Modified"
}

// MARK: - Image item for sheet presentation
private struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct FilesView: View {
    @State private var currentDirectory: URL
    @State private var files: [URL] = []
    @State private var searchText: String = ""
    @State private var isImporting = false
    @State private var imageItem: ImageItem?
    @State private var navigateToFolder: URL?
    @State private var editMode: EditMode = .inactive
    @State private var selectedFiles: Set<URL> = []
    @State private var showExtensionChangeAlert = false
    @State private var pendingRenameFile: URL?
    @State private var pendingNewFileName: String = ""
    @State private var sortOption: SortOption = .name
    @State private var sortAscending: Bool = true
    @State private var selectedFileForInfo: URL?
    @State private var showRenameAlert = false
    @State private var newFileName = ""
    @State private var showExtensionConfirmation = false
    @State private var extensionChangePending: (file: URL, newName: String)?
    @State private var showDestinationPicker = false
    @State private var destinationOperation: FileOperation?
    @State private var showDeleteConfirmation = false

    private struct FileOperation: Identifiable {
        let id = UUID()
        let file: URL
        let isMove: Bool
    }
    
    private let rootURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Files", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Init
    init() {
        _currentDirectory = State(initialValue: {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dir = docs.appendingPathComponent("Files", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }())
    }

    init(currentDirectory: URL) {
        _currentDirectory = State(initialValue: currentDirectory)
    }

    // MARK: - Body
    var body: some View {
        NBNavigationView(.localized("Files")) {
            if #available(iOS 17.0, *) {
                NBListAdaptable {
                    if !filteredFiles.isEmpty {
                        NBSection(.localized("Files"), secondary: filteredFiles.count.description) {
                            ForEach(filteredFiles, id: \.self) { file in
                                fileRow(for: file)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        if !editMode.isEditing {
                                            Button(role: .destructive) { deleteFile(file) } label: {
                                                Label(.localized("Delete"), systemImage: "trash")
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }
                .searchable(text: $searchText, placement: .platform())
                .overlay {
                    if filteredFiles.isEmpty {
                        if #available(iOS 17, *) {
                            ContentUnavailableView {
                                Label(.localized("No Files"), systemImage: "questionmark.app.fill")
                            } description: {
                                Text(.localized("Get started by importing a file."))
                            } actions: {
                                Button {
                                    isImporting = true
                                } label: {
                                    NBButton(.localized("Import"), style: .text)
                                }
                            }
                        }
                    }
                }
                .toolbar {
                    // Left: Edit Button
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    
                    // Right: Conditional group
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if editMode.isEditing {
                            // Delete selected files
                            Button {
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(selectedFiles.isEmpty)
                            
                            // Copy
                            Button {
                                destinationOperation = FileOperation(file: currentDirectory, isMove: false)
                                showDestinationPicker = true
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .disabled(selectedFiles.isEmpty)
                            
                            // Move
                            Button {
                                destinationOperation = FileOperation(file: currentDirectory, isMove: true)
                                showDestinationPicker = true
                            } label: {
                                Image(systemName: "folder")
                            }
                            .disabled(selectedFiles.isEmpty)
                        } else {
                            // Sort menu
                            Menu {
                                ForEach(SortOption.allCases, id: \.self) { option in
                                    Button {
                                        if sortOption == option {
                                            sortAscending.toggle()
                                        } else {
                                            sortOption = option
                                            sortAscending = true
                                        }
                                        loadFiles()
                                    } label: {
                                        HStack {
                                            Text(option.rawValue)
                                            if sortOption == option {
                                                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease")
                            }
                            
                            // Import (+)
                            Button {
                                isImporting = true
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                }
                .environment(\.editMode, $editMode)
                .sheet(isPresented: $isImporting) {
                    DocumentImporter(
                        allowedTypes: [.item] // UPDATED: Allow any file type
                    ) { pickedURL in
                        importFile(from: pickedURL)
                    }
                }
                .background(navigationLink)
                .fullScreenCover(item: $imageItem) { item in
                    ImageViewerView(imageURL: item.url)
                        .ignoresSafeArea()
                }
                // MARK: - Unified Rename + Extension Confirmation Alert
                .alert(isPresented: Binding(
                    get: { showRenameAlert || showExtensionConfirmation || showDeleteConfirmation },
                    set: { value in
                        if !value {
                            showRenameAlert = false
                            showExtensionConfirmation = false
                            showDeleteConfirmation = false
                        }
                    }
                )) {
                    if showDeleteConfirmation {
                        return Alert(
                            title: Text("Delete File\(selectedFiles.count > 1 ? "s" : "")?"),
                            message: Text("Are you sure you want to delete the selected file\(selectedFiles.count > 1 ? "s" : "")? This action cannot be undone."),
                            primaryButton: .destructive(Text("Delete")) {
                                deleteSelectedFiles()
                            },
                            secondaryButton: .cancel {
                                showDeleteConfirmation = false
                            }
                        )
                    } else if showExtensionConfirmation, let pending = extensionChangePending {
                        return Alert(
                            title: Text("Change File Extension?"),
                            message: Text("You changed the file’s extension. Are you sure you want to rename it to “\(pending.newName)”?\n"),
                            primaryButton: .destructive(Text("Rename")) {
                                renameFile(pending.file, to: pending.newName)
                                extensionChangePending = nil
                            },
                            secondaryButton: .cancel {
                                extensionChangePending = nil
                            }
                        )
                    } else {
                        return Alert(
                            title: Text("Rename File"),
                            message: Text("Edit the file name. Changing the extension may affect how the file is opened."),
                            primaryButton: .default(Text("Save")) {
                                guard let file = selectedFileForInfo else { return }
                                let oldExt = file.pathExtension
                                let newExt = URL(fileURLWithPath: newFileName).pathExtension
                                
                                if !newExt.isEmpty && newExt.lowercased() != oldExt.lowercased() {
                                    extensionChangePending = (file, newFileName)
                                    showExtensionConfirmation = true
                                } else {
                                    renameFile(file, to: newFileName)
                                }
                                newFileName = ""
                            },
                            secondaryButton: .cancel {
                                newFileName = ""
                            }
                        )
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        loadFiles()
                    }
                }
                .onChange(of: sortOption) { loadFiles() }
                .onChange(of: sortAscending) { loadFiles() }
            } else {
                // Fallback on earlier versions
            }
        }
        .sheet(item: $destinationOperation, content: { op in
            SelectFolderView(
                root: rootURL,
                onSelect: { folder in
                    performFileOperation(from: selectedFiles, toFolder: folder, isMove: op.isMove)
                    destinationOperation = nil
                }
            )
        })
    }

    // MARK: - Filtered Files
    private var filteredFiles: [URL] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return files
        } else {
            return files.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(searchText) }
        }
    }

    // MARK: - Navigation
    private var navigationLink: some View {
        NavigationLink(
            destination: Group {
                if let folder = navigateToFolder {
                    FilesView(currentDirectory: folder)
                }
            },
            isActive: Binding(
                get: { navigateToFolder != nil },
                set: { if !$0 { navigateToFolder = nil } }
            )
        ) { EmptyView() }
        .hidden()
    }
}

// MARK: - Rows
private extension FilesView {
    @ViewBuilder
    func fileRow(for file: URL) -> some View {
        HStack {
            if editMode.isEditing {
                Image(systemName: selectedFiles.contains(file) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.accentColor)
                    .onTapGesture { toggleFileSelection(file) }
            }

            FileCell(file: file)

            Spacer()

            Button {
                showInfoActionSheet(for: file)
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if editMode.isEditing {
                toggleFileSelection(file)
            } else {
                if isDirectory(file) {
                    if file.lastPathComponent == "Payload" {
                        showPayloadActionSheet(for: file)
                    } else {
                        navigateToFolder = file
                    }
                } else {
                    handleFileTap(file)
                }
            }
        }
        .listRowBackground(Color.clear)
    }
    func performFileOperation(from files: Set<URL>, toFolder folder: URL, isMove: Bool) {
        for file in files {
            let destination = folder.appendingPathComponent(file.lastPathComponent)

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }

                if isMove {
                    try FileManager.default.moveItem(at: file, to: destination)
                } else {
                    try FileManager.default.copyItem(at: file, to: destination)
                }
            } catch {
                print("File operation failed for \(file.lastPathComponent):", error)
            }
        }

        // Clear selection and refresh list
        selectedFiles.removeAll()
        loadFiles()
    }
}

// MARK: - Sheets
private extension FilesView {

    // MARK: File Info Sheet
    @ViewBuilder
    func fileInfoSheet(for file: URL) -> some View {
        if #available(iOS 16.4, *) {
            VStack(spacing: 0) {
                actionButton("Share") {
                    presentShareSheet(for: file)
                }
                
                Divider()
                
                actionButton("Copy To…") {
                    selectedFileForInfo = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        destinationOperation = FileOperation(file: file, isMove: false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showDestinationPicker = true
                        }
                    }
                }
                
                Divider()
                
                actionButton("Move To…") {
                    selectedFileForInfo = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        destinationOperation = FileOperation(file: file, isMove: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showDestinationPicker = true
                        }
                    }
                }
                
                Divider()
                
                actionButton("Rename") {
                    selectedFileForInfo = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showRenamePrompt(for: file)
                    }
                }
                
                Divider()
                
                destructiveButton("Delete") {
                    deleteFile(file)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 26)
            .presentationDetents([.fraction(0.36)]) // slightly taller since more buttons
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(24)
            .presentationBackground(.ultraThinMaterial)
        } else {
            // Fallback on earlier versions
        }
    }

    // MARK: - Shared button styles
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    private func destructiveButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }
}

// MARK: - Logic
private extension FilesView {
    func toggleFileSelection(_ file: URL) {
        if selectedFiles.contains(file) { selectedFiles.remove(file) }
        else { selectedFiles.insert(file) }
    }

    func deleteSelectedFiles() {
        for file in selectedFiles {
            try? FileManager.default.removeItem(at: file)
        }
        selectedFiles.removeAll()
        loadFiles()
    }

    func deleteFile(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
        loadFiles()
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    func loadFiles() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: currentDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .typeIdentifierKey]
        ) else {
            files = []
            return
        }

        var sorted = urls.map { $0.standardizedFileURL }

        switch sortOption {
        case .name:
            sorted.sort {
                sortAscending
                    ? $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased()
                    : $0.lastPathComponent.lowercased() > $1.lastPathComponent.lowercased()
            }
        case .type:
            sorted.sort {
                let ext0 = $0.pathExtension.lowercased()
                let ext1 = $1.pathExtension.lowercased()
                if ext0 == ext1 {
                    return sortAscending
                        ? $0.lastPathComponent < $1.lastPathComponent
                        : $0.lastPathComponent > $1.lastPathComponent
                }
                return sortAscending ? ext0 < ext1 : ext0 > ext1
            }
        case .size:
            sorted.sort {
                let size0 = (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let size1 = (try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sortAscending ? size0 < size1 : size0 > size1
            }
        case .modified:
            sorted.sort {
                let date0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let date1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return sortAscending ? (date0 ?? .distantPast) < (date1 ?? .distantPast) : (date0 ?? .distantPast) > (date1 ?? .distantPast)
            }
        }

        files = sorted
    }

    func importFile(from pickedURL: URL) {
        let dest = currentDirectory.appendingPathComponent(pickedURL.lastPathComponent)
        
        confirmOverwriteIfNeeded(for: dest) {
            do {
                let data = try Data(contentsOf: pickedURL)
                try data.write(to: dest, options: .atomic)
                loadFiles()
            } catch {
                print("Import error:", error)
            }
        }
    }

    func handleFileTap(_ file: URL) {
        switch file.pathExtension.lowercased() {
        case "ipa":
            showIPAActions(for: file)
        case "zip":
            unzipArchive(file)
        case "png", "jpg", "jpeg":
            imageItem = ImageItem(url: file)
        case "plist":
            showPlistOpenAlert(for: file)
        default:
            break
        }
    }

    func navigateToPlistEditor(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }

        let editor = PlistEditorView(plistURL: file)
        let hosting = UIHostingController(rootView: editor)
        hosting.modalPresentationStyle = .formSheet
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(hosting, animated: true)
        }
    }

    func unzipIPA(_ ipaURL: URL) {
        let destination = rootURL.appendingPathComponent(ipaURL.deletingPathExtension().lastPathComponent)

        confirmOverwriteIfNeeded(for: destination) {
            IPAProgressManager.shared.show(name: "Extracting \(ipaURL.lastPathComponent)")

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Create a fresh folder
                    try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

                    // Copy to a .zip temp file since .ipa is a renamed .zip
                    let tempZip = ipaURL.deletingPathExtension().appendingPathExtension("zip")
                    try? FileManager.default.copyItem(at: ipaURL, to: tempZip)

                    // Perform extraction with progress reporting
                    try Zip.unzipFile(
                        tempZip,
                        destination: destination,
                        overwrite: true,
                        password: nil,
                        progress: { progress in
                            DispatchQueue.main.async {
                                IPAProgressManager.shared.update(progress)
                            }
                        }
                    )

                    // Clean up
                    try? FileManager.default.removeItem(at: tempZip)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        IPAProgressManager.shared.complete()
                        loadFiles()
                    }
                } catch {
                    DispatchQueue.main.async {
                        IPAProgressManager.shared.complete()
                        print("IPA unzip failed:", error)
                    }
                }
            }
        }
    }
    
    func unzipArchive(_ zipURL: URL) {
        let destination = zipURL.deletingPathExtension()

        confirmOverwriteIfNeeded(for: destination) {
            IPAProgressManager.shared.show(name: "Unzipping \(zipURL.lastPathComponent)")
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    try Zip.unzipFile(
                        zipURL,
                        destination: destination,
                        overwrite: true,
                        password: nil,
                        progress: { progress in
                            DispatchQueue.main.async {
                                IPAProgressManager.shared.update(progress)
                            }
                        }
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        IPAProgressManager.shared.complete()
                        loadFiles()
                    }
                } catch {
                    DispatchQueue.main.async {
                        IPAProgressManager.shared.complete()
                        print("Failed to unzip:", error)
                    }
                }
            }
        }
    }

    func importToLibrary(_ ipaURL: URL) {
        let id = "FeatherManualDownload_\(UUID().uuidString)"
        let dl = DownloadManager.shared.startArchive(from: ipaURL, id: id)
        try? DownloadManager.shared.handlePachageFile(url: ipaURL, dl: dl)
    }

    func packageIPA(from folder: URL) {
        let parent = folder.deletingLastPathComponent()
        let ipaName = parent.lastPathComponent + ".ipa"
        let ipaPath = parent.appendingPathComponent(ipaName)

        confirmOverwriteIfNeeded(for: ipaPath) {
            IPAProgressManager.shared.show(name: "Packaging \(ipaName)")

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Zip.zipFiles(
                        paths: [folder],
                        zipFilePath: ipaPath,
                        password: nil,
                        progress: { progress in
                            DispatchQueue.main.async {
                                IPAProgressManager.shared.update(progress)
                            }
                        }
                    )

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        IPAProgressManager.shared.complete()
                        loadFiles()
                    }
                } catch {
                    DispatchQueue.main.async {
                        IPAProgressManager.shared.complete()
                        print("IPA packaging failed:", error)
                    }
                }
            }
        }
    }

    func copyFile(_ file: URL) {
        let destination = file.deletingLastPathComponent()
            .appendingPathComponent(file.deletingPathExtension().lastPathComponent + " copy." + file.pathExtension)
        try? FileManager.default.copyItem(at: file, to: destination)
        loadFiles()
    }

    func renameFile(_ file: URL, to newName: String) {
        guard !newName.isEmpty else { return }

        var destination = file.deletingLastPathComponent().appendingPathComponent(newName)
        
        // If the user didn’t type an extension, preserve the original one
        if destination.pathExtension.isEmpty, !file.pathExtension.isEmpty {
            destination.appendPathExtension(file.pathExtension)
        }

        do {
            try FileManager.default.moveItem(at: file, to: destination)
            loadFiles()
        } catch {
            print("Rename failed:", error)
        }
    }
    
    func confirmExtensionChange(file: URL, newName: String) {
        let alert = UIAlertController(
            title: "Change File Extension?",
            message: "You changed the file’s extension. Are you sure you want to rename it to “\(newName)”?",
            preferredStyle: .alert
        )
        
        // Cancel stays gray
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Rename appears RED because of .destructive
        alert.addAction(UIAlertAction(title: "Rename", style: .destructive) { _ in
            renameFile(file, to: newName)
        })
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(alert, animated: true)
        }
    }
    
    func showPlistOpenAlert(for file: URL) {
        let alert = UIAlertController(
            title: nil,
            message: nil,
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "Plist Editor", style: .default) { _ in
            navigateToPlistEditor(file)
        })

        alert.addAction(UIAlertAction(title: "Text Editor", style: .default) { _ in
            navigateToTextEditor(file)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(alert, animated: true)
        }
    }

    func navigateToTextEditor(_ file: URL) {
        guard let data = try? Data(contentsOf: file) else { return }
        var text: String?

        // Try to read as UTF-8; if binary, convert to XML string
        if let str = String(data: data, encoding: .utf8) {
            text = str
        } else if let any = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let xmlData = try? PropertyListSerialization.data(fromPropertyList: any, format: .xml, options: 0),
                  let xmlString = String(data: xmlData, encoding: .utf8) {
            text = xmlString
        }

        guard let content = text else { return }

        let textView = TextEditorView(fileURL: file, text: content)
        let hosting = UIHostingController(rootView: textView)
        hosting.modalPresentationStyle = .fullScreen

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(hosting, animated: true)
        }
    }
    
    func showRenamePrompt(for file: URL) {
        let oldName = file.lastPathComponent
        var textField: UITextField?

        let alert = UIAlertController(
            title: "Rename File",
            message: "Please enter a new file name.",
            preferredStyle: .alert
        )
        
        alert.addTextField { tf in
            tf.text = oldName
            textField = tf
            tf.clearButtonMode = .whileEditing
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            guard let newName = textField?.text, !newName.isEmpty else { return }
            
            let oldExt = file.pathExtension
            let newExt = URL(fileURLWithPath: newName).pathExtension
            
            if !newExt.isEmpty && newExt.lowercased() != oldExt.lowercased() {
                confirmExtensionChange(file: file, newName: newName)
            } else {
                renameFile(file, to: newName)
            }
        })
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(alert, animated: true)
        }
    }
    
    func presentShareSheet(for file: URL) {
        let activityVC = UIActivityViewController(activityItems: [file], applicationActivities: nil)

        // Present from the root of the main key window
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else { return }

        DispatchQueue.main.async {
            root.present(activityVC, animated: true)
        }
    }
    
    func confirmOverwriteIfNeeded(for target: URL, action: @escaping () -> Void) {
        if FileManager.default.fileExists(atPath: target.path) {
            let alert = UIAlertController(
                title: "File Already Exists",
                message: "A file or folder named “\(target.lastPathComponent)” already exists. Would you like to replace it?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Overwrite", style: .destructive) { _ in
                try? FileManager.default.removeItem(at: target)
                action()
            })
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                root.present(alert, animated: true)
            }
        } else {
            action()
        }
    }
}

// MARK: - File Picker Delegate
private class FilePickerDelegate: NSObject, UIDocumentPickerDelegate {
    let file: URL
    let isMove: Bool
    let onComplete: () -> Void

    init(file: URL, isMove: Bool, onComplete: @escaping () -> Void) {
        self.file = file
        self.isMove = isMove
        self.onComplete = onComplete
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let destFolder = urls.first else { return }
        guard destFolder.startAccessingSecurityScopedResource() else { return }
        defer { destFolder.stopAccessingSecurityScopedResource() }

        let destination = destFolder.appendingPathComponent(file.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            if isMove {
                try FileManager.default.moveItem(at: file, to: destination)
            } else {
                try FileManager.default.copyItem(at: file, to: destination)
            }
            onComplete()
        } catch {
            print("File operation failed:", error)
        }
    }
}

// MARK: - Native iOS Action Sheets (Unified Full-Width Style)
private extension FilesView {
    func presentActionSheet(actions: [UIAlertAction]) {
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        actions.forEach { controller.addAction($0) }

        // Present from the root scene
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            if let popover = controller.popoverPresentationController {
                // Make sure it appears anchored at the bottom center
                popover.sourceView = root.view
                popover.sourceRect = CGRect(
                    x: root.view.bounds.midX,
                    y: root.view.bounds.maxY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
            root.present(controller, animated: true)
        }
    }

    // MARK: Info Sheet
    func showInfoActionSheet(for file: URL) {
        presentActionSheet(actions: [
            UIAlertAction(title: "Share", style: .default) { _ in presentShareSheet(for: file) },
            UIAlertAction(title: "Copy To…", style: .default) { _ in
                destinationOperation = FileOperation(file: file, isMove: false)
                showDestinationPicker = true
            },
            UIAlertAction(title: "Move To…", style: .default) { _ in
                destinationOperation = FileOperation(file: file, isMove: true)
                showDestinationPicker = true
            },
            UIAlertAction(title: "Rename", style: .default) { _ in showRenamePrompt(for: file) },
            UIAlertAction(title: "Delete", style: .destructive) { _ in deleteFile(file) },
            UIAlertAction(title: "Cancel", style: .cancel)
        ])
    }

    // MARK: Payload Sheet
    func showPayloadActionSheet(for folder: URL) {
        presentActionSheet(actions: [
            UIAlertAction(title: "View Contents", style: .default) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { navigateToFolder = folder }
            },
            UIAlertAction(title: "Package IPA", style: .default) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { packageIPA(from: folder) }
            },
            UIAlertAction(title: "Cancel", style: .cancel)
        ])
    }

    // MARK: IPA Sheet
    func showIPAActions(for ipa: URL) {
        presentActionSheet(actions: [
            UIAlertAction(title: "Unzip IPA", style: .default) { _ in unzipIPA(ipa) },
            UIAlertAction(title: "Import to Library", style: .default) { _ in importToLibrary(ipa) },
            UIAlertAction(title: "Cancel", style: .cancel)
        ])
    }
}
