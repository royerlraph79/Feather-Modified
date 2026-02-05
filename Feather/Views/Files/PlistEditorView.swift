//
//  PlistEditorView.swift
//  Feather
//
//  Full recursive plist editor: dicts, arrays, scalars, add/delete/reorder, save.
//  Works for editing CFBundleIcons and other nested keys.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation
import CoreFoundation

// MARK: - Plist Node Model

indirect enum PlistNode: Equatable, Identifiable {
    case dict([String: PlistNode])
    case array([PlistNode])
    case string(String)
    case number(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case null

    var id: UUID { UUID() } // ephemeral; used for SwiftUI identity

    var isContainer: Bool {
        if case .dict = self { return true }
        if case .array = self { return true }
        return false
    }

    // Type name for UI
    var kindName: String {
        switch self {
        case .dict: return "Dictionary"
        case .array: return "Array"
        case .string: return "String"
        case .number: return "Number"
        case .bool: return "Boolean"
        case .date: return "Date"
        case .data: return "Data"
        case .null: return "Null"
        }
    }
}

// MARK: - Any <-> PlistNode bridge

private func anyToNode(_ any: Any) -> PlistNode {
    switch any {
    case let d as [String: Any]:
        var dict: [String: PlistNode] = [:]
        for (k, v) in d { dict[k] = anyToNode(v) }
        return .dict(dict)
    case let arr as [Any]:
        return .array(arr.map(anyToNode))
    case let s as String:
        return .string(s)
    case let n as NSNumber:
        // NSNumber can be bool or number; detect
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return .bool(n.boolValue)
        } else {
            return .number(n.doubleValue)
        }
    case let b as Bool:
        return .bool(b)
    case let date as Date:
        return .date(date)
    case let data as Data:
        return .data(data)
    default:
        return .null
    }
}

private func nodeToAny(_ node: PlistNode) -> Any {
    switch node {
    case .dict(let d):
        var out: [String: Any] = [:]
        for (k, v) in d { out[k] = nodeToAny(v) }
        return out
    case .array(let arr):
        return arr.map(nodeToAny)
    case .string(let s): return s
    case .number(let n): return n
    case .bool(let b): return b
    case .date(let date): return date
    case .data(let data): return data
    case .null: return NSNull()
    }
}

// MARK: - Utilities

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
    init?(hex: String) {
        let hex = hex.replacingOccurrences(of: " ", with: "")
        guard hex.count % 2 == 0 else { return nil }
        var data = Data()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            let byteString = hex[idx..<next]
            if let num = UInt8(byteString, radix: 16) {
                data.append(num)
            } else {
                return nil
            }
            idx = next
        }
        self = data
    }
}

// MARK: - Editor Entry

struct PlistEditorView: View {
    let plistURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var rootNode: PlistNode = .dict([:])
    @State private var loadError: String?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            NodeEditorView(node: $rootNode, title: plistURL.lastPathComponent, isRoot: true)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { savePlist() }.bold()
                    }
                }
                .alert("Error", isPresented: .constant(loadError != nil || saveError != nil), actions: {
                    Button("OK") {
                        loadError = nil
                        saveError = nil
                    }
                }, message: {
                    Text(loadError ?? saveError ?? "")
                })
                .onAppear(perform: loadPlist)
        }
    }

    private func loadPlist() {
        do {
            let data = try Data(contentsOf: plistURL)
            print("Loading plist:", plistURL.path, "size:", data.count)

            var format = PropertyListSerialization.PropertyListFormat.xml
            var any: Any?
            do {
                any = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
                print("Loaded with PropertyListSerialization (format: \(format))")
            } catch {
                print("PropertyListSerialization failed: \(error.localizedDescription)")
            }

            if any == nil {
                var cfFormat = CFPropertyListFormat.binaryFormat_v1_0
                var cfError: Unmanaged<CFError>?
                if let cfObj = CFPropertyListCreateWithData(
                    kCFAllocatorDefault,
                    data as CFData,
                    CFOptionFlags(0x3), // mutable containers and leaves
                    &cfFormat,
                    &cfError
                )?.takeRetainedValue() {
                    any = cfObj as Any
                    print("Loaded with CFPropertyListCreateWithData (format: \(cfFormat.rawValue))")
                } else if let err = cfError?.takeRetainedValue() {
                    print("CFPropertyListCreateWithData failed:", err)
                }
            }

            guard let object = any else {
                DispatchQueue.main.async {
                    loadError = "Unable to decode plist."
                }
                print("No object returned from both decoding attempts.")
                return
            }

            // --- Convert for editor (ensure state changes happen on main thread)
            if let dict = object as? [String: Any] {
                DispatchQueue.main.async {
                    rootNode = .dict(anyToNode(dict).asDict)
                }
            } else if let array = object as? [Any] {
                DispatchQueue.main.async {
                    rootNode = anyToNode(array)
                }
            } else {
                DispatchQueue.main.async {
                    loadError = "Unsupported root type: \(type(of: object))"
                }
            }

        } catch {
            DispatchQueue.main.async {
                loadError = "Failed to load plist: \(error.localizedDescription)"
            }
            print("\(error)")
        }
    }
    
    private func savePlist() {
        do {
            let rootAny = nodeToAny(rootNode)
            let data = try PropertyListSerialization.data(fromPropertyList: rootAny, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            dismiss()
        } catch {
            saveError = "Failed to save plist: \(error.localizedDescription)"
        }
    }
}

// MARK: - Node Editor Router

private struct NodeEditorView: View {
    @Binding var node: PlistNode
    let title: String
    var isRoot: Bool = false

    var body: some View {
        Group {
            switch node {
            case .dict:
                DictEditor(node: $node, title: title, isRoot: isRoot)
            case .array:
                ArrayEditor(node: $node, title: title)
            case .string, .number, .bool, .date, .data, .null:
                ScalarEditor(node: $node, title: title)
            }
        }
    }
}

// MARK: - Dictionary Editor

private struct DictEditor: View {
    @Binding var node: PlistNode
    let title: String
    var isRoot: Bool

    @State private var kv: [(String, PlistNode)] = []
    @State private var showAddSheet = false
    @State private var newKey = ""
    @State private var newType: PlistNode = .string("")

    var body: some View {
        List {
            ForEach(kv.indices, id: \.self) { i in
                NavigationLink {
                    NodeEditorView(node: Binding(
                        get: { kv[i].1 },
                        set: { kv[i].1 = $0; pushBack() }
                    ), title: kv[i].0)
                } label: {
                    HStack {
                        Text(kv[i].0).font(.body)
                        Spacer()
                        Text(kv[i].1.kindName)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        kv.remove(at: i)
                        pushBack()
                    } label: { Label("Delete", systemImage: "trash") }

                    Button {
                        promptRename(index: i)
                    } label: { Label("Rename", systemImage: "pencil") }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newKey = ""
                    newType = .string("")
                    showAddSheet = true
                } label: { Label("Add", systemImage: "plus") }
            }
        }
        .onAppear(perform: pullIn)
        .onChange(of: node) { _ in
            pullIn()
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                Form {
                    Section("Key") {
                        TextField("Key", text: $newKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.none)
                    }
                    Section("Type") {
                        TypePicker(selection: $newType)
                        ScalarInlineEditor(node: $newType)
                    }
                }
                .navigationTitle("New Entry")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showAddSheet = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add") {
                            guard !newKey.isEmpty else { return }
                            kv.append((newKey, newType))
                            kv.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
                            pushBack()
                            showAddSheet = false
                        }.bold()
                    }
                }
            }
        }
    }

    private func pullIn() {
        if case .dict(let d) = node {
            kv = d.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        }
    }
    private func pushBack() {
        var d: [String: PlistNode] = [:]
        for (k, v) in kv { d[k] = v }
        node = .dict(d)
    }

    private func promptRename(index i: Int) {
        // simple rename inline using alert-like sheet
        var entry = kv[i]
        let oldKey = entry.0
        let controller = UIAlertController(title: "Rename Key", message: oldKey, preferredStyle: .alert)
        controller.addTextField { tf in
            tf.text = oldKey
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        controller.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            if let newText = controller.textFields?.first?.text, !newText.isEmpty {
                entry.0 = newText
                kv[i] = entry
                kv.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
                pushBack()
            }
        }))
        // present
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(controller, animated: true)
        }
    }
}

// MARK: - Array Editor

private struct ArrayEditor: View {
    @Binding var node: PlistNode
    let title: String

    @State private var elements: [PlistNode] = []
    @State private var showAddSheet = false
    @State private var newType: PlistNode = .string("")

    var body: some View {
        List {
            ForEach(elements.indices, id: \.self) { i in
                NavigationLink {
                    NodeEditorView(node: Binding(
                        get: { elements[i] },
                        set: { elements[i] = $0; pushBack() }
                    ), title: "\(title)[\(i)]")
                } label: {
                    HStack {
                        Text("[\(i)]").monospaced()
                        Spacer()
                        Text(elements[i].kindName).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { idx in
                elements.remove(atOffsets: idx)
                pushBack()
            }
            .onMove { from, to in
                elements.move(fromOffsets: from, toOffset: to)
                pushBack()
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newType = .string("")
                    showAddSheet = true
                } label: { Label("Add", systemImage: "plus") }
            }
        }
        .onAppear(perform: pullIn)
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                Form {
                    Section("Type") {
                        TypePicker(selection: $newType)
                        ScalarInlineEditor(node: $newType)
                    }
                }
                .navigationTitle("New Item")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showAddSheet = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add") {
                            elements.append(newType)
                            pushBack()
                            showAddSheet = false
                        }.bold()
                    }
                }
            }
        }
    }

    private func pullIn() {
        if case .array(let arr) = node {
            elements = arr
        }
    }
    private func pushBack() {
        node = .array(elements)
    }
}

// MARK: - Scalar Editor

private struct ScalarEditor: View {
    @Binding var node: PlistNode
    let title: String

    var body: some View {
        Form {
            ScalarInlineEditor(node: $node)
        }
        .navigationTitle(title)
    }
}

private struct ScalarInlineEditor: View {
    @Binding var node: PlistNode

    @State private var stringValue: String = ""
    @State private var numberValue: String = ""
    @State private var boolValue: Bool = false
    @State private var dateValue: Date = Date()
    @State private var dataHex: String = ""

    var body: some View {
        switch node {
        case .string(let s):
            TextField("String", text: Binding(
                get: { stringValue.isEmpty ? s : stringValue },
                set: { stringValue = $0; node = .string($0) }
            ))
            .onAppear { stringValue = s }

        case .number(let n):
            TextField("Number", text: Binding(
                get: { numberValue.isEmpty ? String(n) : numberValue },
                set: {
                    numberValue = $0
                    if let val = Double($0) { node = .number(val) }
                }
            ))
            .keyboardType(.numbersAndPunctuation)
            .onAppear { numberValue = String(n) }

        case .bool(let b):
            Toggle("Value", isOn: Binding(
                get: { boolValue },
                set: { boolValue = $0; node = .bool($0) }
            ))
            .onAppear { boolValue = b }

        case .date(let d):
            DatePicker("Date", selection: Binding(
                get: { dateValue },
                set: { dateValue = $0; node = .date($0) }
            ), displayedComponents: [.date, .hourAndMinute])
            .onAppear { dateValue = d }

        case .data(let data):
            TextEditor(text: Binding(
                get: { dataHex.isEmpty ? data.hexString : dataHex },
                set: {
                    dataHex = $0
                    if let newData = Data(hex: $0) { node = .data(newData) }
                }
            ))
            .frame(minHeight: 120)
            .font(.system(.footnote, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

        case .null:
            Text("Null (no value)").foregroundStyle(.secondary)

        case .dict, .array:
            EmptyView() // containers handled elsewhere
        }
    }
}

// MARK: - Type Picker

private struct TypePicker: View {
    @Binding var selection: PlistNode

    var body: some View {
        Picker("Type", selection: Binding(
            get: { selection.kindName },
            set: { name in selection = pickerToNode(name: name) }
        )) {
            Text("String").tag("String")
            Text("Number").tag("Number")
            Text("Boolean").tag("Boolean")
            Text("Date").tag("Date")
            Text("Data").tag("Data")
            Text("Dictionary").tag("Dictionary")
            Text("Array").tag("Array")
            Text("Null").tag("Null")
        }
        .pickerStyle(.menu)
    }

    private func pickerToNode(name: String) -> PlistNode {
        switch name {
        case "String": return .string("")
        case "Number": return .number(0)
        case "Boolean": return .bool(false)
        case "Date": return .date(Date())
        case "Data": return .data(Data())
        case "Dictionary": return .dict([:])
        case "Array": return .array([])
        case "Null": return .null
        default: return .string("")
        }
    }
}

private extension PlistNode {
    var asDict: [String: PlistNode] {
        if case .dict(let d) = self { return d }
        return [:]
    }
}
