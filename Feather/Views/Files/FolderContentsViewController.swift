//
//  FolderContentsViewController.swift
//  Feather
//
//  Created by David Wojcik III on 11/3/25.
//


import UIKit

final class FolderContentsViewController: UITableViewController {
    private let folder: URL
    private var items: [URL] = []

    init(folderURL: URL) {
        folder = folderURL
        super.init(style: .plain)
        title = folderURL.lastPathComponent
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        refresh()
    }

    private func refresh() {
        items = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                              includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsHiddenFiles])) ?? []
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let u = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = u.lastPathComponent
        let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        config.secondaryText = isDir ? "Folder" : u.pathExtension.uppercased()
        cell.contentConfiguration = config
        cell.accessoryType = isDir ? .disclosureIndicator : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let url = items[indexPath.row]
        tableView.deselectRow(at: indexPath, animated: true)
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir {
            let vc = FolderContentsViewController(folderURL: url)
            navigationController?.pushViewController(vc, animated: true)
        } else {
            let doc = UIDocumentInteractionController(url: url)
            doc.delegate = self
            doc.presentPreview(animated: true)
        }
    }
}

extension FolderContentsViewController: UIDocumentInteractionControllerDelegate {
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController { self }
}
