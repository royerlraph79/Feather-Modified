//
//  LibraryAppIconView.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import SwiftUI
import NimbleExtensions
import NimbleViews
import Zip
import IDeviceSwift

// MARK: - View
struct LibraryCellView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.editMode) private var editMode

    var certInfo: Date.ExpirationInfo? {
        Storage.shared.getCertificate(from: app)?.expiration?.expirationInfo()
    }
    
    var certRevoked: Bool {
        Storage.shared.getCertificate(from: app)?.revoked == true
    }
    
    var app: AppInfoPresentable
    @Binding var selectedInfoAppPresenting: AnyApp?
    @Binding var selectedSigningAppPresenting: AnyApp?
    @Binding var selectedInstallAppPresenting: AnyApp?
    @Binding var selectedAppUUIDs: Set<String>
    
    // Dylib picker state
    @State private var dylibPickerData: DylibPickerData?
    
    // Icon picker state
    @State private var iconPickerData: IconPickerData?
    
    struct DylibPickerData: Identifiable {
        let id = UUID()
        var extractedDylibs: [DylibInfo]
        var selectedDylibs: Set<UUID>
        var appName: String
        var extractionFolder: URL
    }
    
    struct IconPickerData: Identifiable {
        let id = UUID()
        var extractedIcons: [IconInfo]
        var selectedIcons: Set<UUID>
        var appName: String
        var extractionFolder: URL
    }
    
    // MARK: Selections
    private var _isSelected: Bool {
        guard let uuid = app.uuid else { return false }
        return selectedAppUUIDs.contains(uuid)
    }
    
    private func _toggleSelection() {
        guard let uuid = app.uuid else { return }
        if selectedAppUUIDs.contains(uuid) {
            selectedAppUUIDs.remove(uuid)
        } else {
            selectedAppUUIDs.insert(uuid)
        }
    }
    
    // MARK: Body
    var body: some View {
        let isRegular = horizontalSizeClass != .compact
        let isEditing = editMode?.wrappedValue == .active
        
        HStack(spacing: 18) {
            if isEditing {
                Button {
                    _toggleSelection()
                } label: {
                    Image(systemName: _isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(_isSelected ? .accentColor : .secondary)
                        .font(.title2)
                }
                .buttonStyle(.borderless)
            }
            
            FRAppIconView(app: app, size: 57)
            
            NBTitleWithSubtitleView(
                title: app.name ?? .localized("Unknown"),
                subtitle: _desc,
                linelimit: 0
            )
            
            if !isEditing {
                _buttonActions(for: app)
            }
        }
        .padding(isRegular ? 12 : 0)
        .background(
            isRegular
            ? RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(_isSelected && isEditing ? Color.accentColor.opacity(0.1) : Color(.quaternarySystemFill))
            : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                _toggleSelection()
            }
        }
        .swipeActions {
            if !isEditing {
                _actions(for: app)
            }
        }
        .contextMenu {
            if !isEditing {
                _contextActions(for: app)
                Divider()
                _contextActionsExtra(for: app)
                Divider()
                _actions(for: app)
            }
        }
        .sheet(item: $dylibPickerData) { data in
            DylibPickerView(
                dylibs: data.extractedDylibs,
                selectedDylibs: Binding(
                    get: { data.selectedDylibs },
                    set: { newValue in
                        if var currentData = dylibPickerData {
                            currentData.selectedDylibs = newValue
                            dylibPickerData = currentData
                        }
                    }
                ),
                appName: data.appName,
                onSave: {
                    if let pickerData = dylibPickerData {
                        finalizeDylibSelection(data: pickerData)
                    }
                    dylibPickerData = nil
                },
                onCancel: {
                    if let pickerData = dylibPickerData {
                        try? FileManager.default.removeItem(at: pickerData.extractionFolder)
                    }
                    dylibPickerData = nil
                }
            )
        }
        .sheet(item: $iconPickerData) { data in
            IconPickerView(
                icons: data.extractedIcons,
                selectedIcons: Binding(
                    get: { data.selectedIcons },
                    set: { newValue in
                        if var currentData = iconPickerData {
                            currentData.selectedIcons = newValue
                            iconPickerData = currentData
                        }
                    }
                ),
                appName: data.appName,
                onSave: {
                    if let pickerData = iconPickerData {
                        finalizeIconSelection(data: pickerData)
                    }
                    iconPickerData = nil
                },
                onCancel: {
                    if let pickerData = iconPickerData {
                        try? FileManager.default.removeItem(at: pickerData.extractionFolder)
                    }
                    iconPickerData = nil
                }
            )
        }
    }
    
    private var _desc: String {
        if let version = app.version, let id = app.identifier {
            return "\(version) • \(id)"
        } else {
            return .localized("Unknown")
        }
    }
}


// MARK: - Extension: View
extension LibraryCellView {
    @ViewBuilder
    private func _actions(for app: AppInfoPresentable) -> some View {
        Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
            Storage.shared.deleteApp(for: app)
        }
    }
    
    @ViewBuilder
    private func _contextActions(for app: AppInfoPresentable) -> some View {
        Button(.localized("Get Info"), systemImage: "info.circle") {
            selectedInfoAppPresenting = AnyApp(base: app)
        }
    }
    
    @ViewBuilder
    private func _contextActionsExtra(for app: AppInfoPresentable) -> some View {
        if app.isSigned {
            if let id = app.identifier {
                Button(.localized("Open"), systemImage: "app.badge.checkmark") {
                    UIApplication.openApp(with: id)
                }
            }
            Button(.localized("Install"), systemImage: "square.and.arrow.down") {
                selectedInstallAppPresenting = AnyApp(base: app)
            }
            Button(.localized("Re-sign"), systemImage: "signature") {
                selectedSigningAppPresenting = AnyApp(base: app)
            }
            Button(.localized("Export"), systemImage: "square.and.arrow.up") {
                selectedInstallAppPresenting = AnyApp(base: app, archive: true)
            }
            Button("Extract Dylibs", systemImage: "doc.zipper") {
                Task {
                    await extractDylibsFromApp(app)
                }
            }
            Button("Extract Icons", systemImage: "app.badge") {
                Task {
                    await extractIconsFromApp(app)
                }
            }
            Button("Import IPA", systemImage: "square.and.arrow.up.on.square") {
                Task {
                    await importAppAsIPA(app)
                }
            }
        } else {
            Button(.localized("Install"), systemImage: "square.and.arrow.down") {
                selectedInstallAppPresenting = AnyApp(base: app)
            }
            Button(.localized("Sign"), systemImage: "signature") {
                selectedSigningAppPresenting = AnyApp(base: app)
            }
            Button("Extract Dylibs", systemImage: "doc.zipper") {
                Task {
                    await extractDylibsFromApp(app)
                }
            }
            Button("Extract Icons", systemImage: "app.badge") {
                Task {
                    await extractIconsFromApp(app)
                }
            }
            Button("Import IPA", systemImage: "square.and.arrow.up.on.square") {
                Task {
                    await importAppAsIPA(app)
                }
            }
        }
    }
    
    @ViewBuilder
    private func _buttonActions(for app: AppInfoPresentable) -> some View {
        Group {
            if app.isSigned {
                Button {
                    selectedInstallAppPresenting = AnyApp(base: app)
                } label: {
                    FRExpirationPillView(
                        title: .localized("Install"),
                        revoked: certRevoked,
                        expiration: certInfo
                    )
                }
            } else {
                Button {
                    selectedSigningAppPresenting = AnyApp(base: app)
                } label: {
                    FRExpirationPillView(
                        title: .localized("Sign"),
                        revoked: false,
                        expiration: nil
                    )
                }
            }
        }
        .buttonStyle(.borderless)
    }
    
    // MARK: - Dylib Extraction
    private func extractDylibsFromApp(_ app: AppInfoPresentable) async {
        guard let appBundleURL = Storage.shared.getAppDirectory(for: app) else {
            print("Could not get app directory")
            return
        }
        
        print("Using app bundle at: \(appBundleURL.path)")
        
        let appName = app.name ?? "Unknown"
        let sanitizedAppName = appName.replacingOccurrences(of: "/", with: "-")
        
        do {
            let allDylibs = try await DylibExtractor.extractDylibs(from: appBundleURL, appFolderName: sanitizedAppName)
            
            let dylibsOnly = allDylibs.filter { $0.name.lowercased().hasSuffix(".dylib") }
            
            print("Successfully extracted \(dylibsOnly.count) dylibs (filtered from \(allDylibs.count) total files) from \(app.name ?? "app")")
            
            let dylibsDir = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask)[0]
                .appendingPathComponent("ExtractedDylibs")
                .appendingPathComponent(sanitizedAppName)
            
            if FileManager.default.fileExists(atPath: dylibsDir.path), !dylibsOnly.isEmpty {
                let allExtractedFiles = allDylibs.filter { !$0.name.lowercased().hasSuffix(".dylib") }
                for file in allExtractedFiles {
                    if let url = file.extractedURL {
                        try? FileManager.default.removeItem(at: url)
                        print("Removed non-dylib file: \(file.name)")
                    }
                }
                
                await MainActor.run {
                    self.dylibPickerData = DylibPickerData(
                        extractedDylibs: dylibsOnly,
                        selectedDylibs: Set(dylibsOnly.map { $0.id }),
                        appName: sanitizedAppName,
                        extractionFolder: dylibsDir
                    )
                }
            } else if dylibsOnly.isEmpty {
                print("No .dylib files found in extraction")
            }
        } catch {
            await MainActor.run {
                print("Failed to extract dylibs: \(error)")
            }
        }
    }
    
    private func finalizeDylibSelection(data: DylibPickerData) {
        for dylib in data.extractedDylibs {
            if !data.selectedDylibs.contains(dylib.id), let url = dylib.extractedURL {
                try? FileManager.default.removeItem(at: url)
                print("Deleted: \(dylib.name)")
            }
        }
        
        print("Kept \(data.selectedDylibs.count) dylibs")
        showFolderInFiles(url: data.extractionFolder)
    }
    
    // MARK: - Icon Extraction
    private func extractIconsFromApp(_ app: AppInfoPresentable) async {
        guard let appBundleURL = Storage.shared.getAppDirectory(for: app) else {
            print("Could not get app directory")
            return
        }
        
        print("Using app bundle at: \(appBundleURL.path)")
        
        let appName = app.name ?? "Unknown"
        let sanitizedAppName = appName.replacingOccurrences(of: "/", with: "-")
        
        do {
            let allIcons = try await IconExtractor.extractIcons(from: appBundleURL, appFolderName: sanitizedAppName)
            
            print("Successfully extracted \(allIcons.count) icons from \(app.name ?? "app")")
            
            let iconsDir = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask)[0]
                .appendingPathComponent("ExtractedIcons")
                .appendingPathComponent(sanitizedAppName)
            
            if FileManager.default.fileExists(atPath: iconsDir.path), !allIcons.isEmpty {
                await MainActor.run {
                    self.iconPickerData = IconPickerData(
                        extractedIcons: allIcons,
                        selectedIcons: Set(allIcons.map { $0.id }),
                        appName: sanitizedAppName,
                        extractionFolder: iconsDir
                    )
                }
            }
        } catch {
            await MainActor.run {
                print("Failed to extract icons: \(error)")
            }
        }
    }
    
    private func finalizeIconSelection(data: IconPickerData) {
        for icon in data.extractedIcons {
            if !data.selectedIcons.contains(icon.id), let url = icon.extractedURL {
                try? FileManager.default.removeItem(at: url)
                print("Deleted: \(icon.name)")
            }
        }
        
        print("Kept \(data.selectedIcons.count) icons")
        showFolderInFiles(url: data.extractionFolder)
    }

    private func showFolderInFiles(url: URL) {
        if let sharedURL = url.toSharedDocumentsURL() {
            UIApplication.open(sharedURL)
        }
    }
}

// MARK: - Dylib Picker View
struct DylibPickerView: View {
    let dylibs: [DylibInfo]
    @Binding var selectedDylibs: Set<UUID>
    let appName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(dylibs) { dylib in
                        Button {
                            if selectedDylibs.contains(dylib.id) {
                                selectedDylibs.remove(dylib.id)
                            } else {
                                selectedDylibs.insert(dylib.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedDylibs.contains(dylib.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedDylibs.contains(dylib.id) ? .blue : .gray)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dylib.name)
                                        .font(.body)
                                    
                                    Text(dylib.formattedSize)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Select Dylibs to Keep")
                } footer: {
                    Text("\(selectedDylibs.count) of \(dylibs.count) selected")
                }
            }
            .navigationTitle("Extract from \(appName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(selectedDylibs.isEmpty)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button(selectedDylibs.count == dylibs.count ? "Deselect All" : "Select All") {
                            if selectedDylibs.count == dylibs.count {
                                selectedDylibs.removeAll()
                            } else {
                                selectedDylibs = Set(dylibs.map { $0.id })
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - Icon Picker View
struct IconPickerView: View {
    let icons: [IconInfo]
    @Binding var selectedIcons: Set<UUID>
    let appName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(icons) { icon in
                        Button {
                            if selectedIcons.contains(icon.id) {
                                selectedIcons.remove(icon.id)
                            } else {
                                selectedIcons.insert(icon.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIcons.contains(icon.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedIcons.contains(icon.id) ? .blue : .gray)
                                
                                Image(uiImage: icon.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(12)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(icon.name)
                                        .font(.body)
                                    
                                    HStack {
                                        Text(icon.formattedSize)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text("•")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text("\(Int(icon.image.size.width))×\(Int(icon.image.size.height))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Select Icons to Keep")
                } footer: {
                    Text("\(selectedIcons.count) of \(icons.count) selected")
                }
            }
            .navigationTitle("Extract from \(appName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(selectedIcons.isEmpty)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button(selectedIcons.count == icons.count ? "Deselect All" : "Select All") {
                            if selectedIcons.count == icons.count {
                                selectedIcons.removeAll()
                            } else {
                                selectedIcons = Set(icons.map { $0.id })
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - IPA Packaging
struct IPAProgressView: View {
    let name: String
    let progress: Double
    let totalBytes: Int64?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.subheadline)
                .lineLimit(1)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
            
            HStack {
                Text("\(Int(progress * 100))%")
                    .contentTransition(.numericText())
                Spacer()
                if let totalBytes {
                    Text(totalBytes.formattedByteCount)
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 4)
        .padding(.top, 6)
    }
}

extension LibraryCellView {
    private func importAppAsIPA(_ app: AppInfoPresentable) async {
        guard let appBundleURL = Storage.shared.getAppDirectory(for: app) else { return }

        let appName = app.name ?? "UnknownApp"
        let sanitizedAppName = appName.replacingOccurrences(of: "/", with: "-")
        let fm = FileManager.default

        // Destination path in Files
        let filesDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Files", isDirectory: true)
        try? fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
        let ipaPath = filesDir.appendingPathComponent("\(sanitizedAppName).ipa")

        // Preflight conflict check (before any heavy work)
        if fm.fileExists(atPath: ipaPath.path) {
            let shouldOverwrite = await confirmOverwrite(fileName: "\(sanitizedAppName).ipa")
            guard shouldOverwrite else { return } // user canceled

            // Try removing now so the move later is straightforward
            do {
                try fm.removeItem(at: ipaPath)
            } catch {
                print("Failed to remove existing IPA: \(error)")
                return
            }
        }

        // Show global progress UI only after user accepted (or no conflict)
        await MainActor.run {
            IPAProgressManager.shared.show(name: "Importing \(appName)")
        }

        // Do the work off the main actor
        Task.detached(priority: .userInitiated) {
            do {
                // Build Payload structure
                let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let payloadDir = tempDir.appendingPathComponent("Payload", isDirectory: true)
                try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)
                let destApp = payloadDir.appendingPathComponent(appBundleURL.lastPathComponent)
                try fm.copyItem(at: appBundleURL, to: destApp)

                // Zip Payload → temp zip
                let zipPath = tempDir.appendingPathComponent("\(sanitizedAppName).zip")
                try await Zip.zipFiles(
                    paths: [payloadDir],
                    zipFilePath: zipPath,
                    password: nil,
                    progress: { progress in
                        DispatchQueue.main.async {
                            IPAProgressManager.shared.update(progress)
                        }
                    }
                )

                // Move to Files as .ipa
                do {
                    try fm.moveItem(at: zipPath, to: ipaPath)
                } catch {
                    // If something recreated the file, try removing then re-move
                    if fm.fileExists(atPath: ipaPath.path) {
                        try fm.removeItem(at: ipaPath)
                        try fm.moveItem(at: zipPath, to: ipaPath)
                    } else {
                        throw error
                    }
                }

                print("Imported \(sanitizedAppName) as IPA at \(ipaPath.path)")
                DispatchQueue.main.async {
                    IPAProgressManager.shared.complete()
                }

                // Clean up temp folder
                try? fm.removeItem(at: tempDir)

            } catch {
                print("Error importing IPA:", error)
                DispatchQueue.main.async {
                    IPAProgressManager.shared.complete() // or call a `.hide()` if you prefer
                }
            }
        }
    }

    /// Presents an overwrite confirmation and resolves to true if user selects "Overwrite".
    private func confirmOverwrite(fileName: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "File Already Exists",
                message: "\(fileName) already exists in Files.\nDo you want to overwrite it?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: "Overwrite", style: .destructive) { _ in
                continuation.resume(returning: true)
            })

            // Present from top VC (Feather already uses this helper)
            UIApplication.topViewController()?.present(alert, animated: true)
        }
    }
}
