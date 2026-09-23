import AppKit
import Foundation
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    private let status = NSTextField(labelWithString: "Reading shared website…")
    private let saveButton = NSButton(title: "Save to Aether", target: nil, action: nil)
    private var sharedURL: URL?
    private var sharedTitle = ""

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 132))
        status.lineBreakMode = .byTruncatingMiddle
        status.frame = NSRect(x: 20, y: 76, width: 320, height: 35)
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.isEnabled = false
        saveButton.frame = NSRect(x: 206, y: 22, width: 134, height: 32)
        container.addSubview(status)
        container.addSubview(saveButton)
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        sharedTitle = items.compactMap { $0.attributedTitle?.string }.first ?? ""
        guard let provider = items.flatMap({ $0.attachments ?? [] })
            .first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) })
        else {
            status.stringValue = "No website address was shared."
            return
        }
        provider.loadObject(ofClass: NSURL.self) { [weak self] item, _ in
            let url = (item as? NSURL).map { $0 as URL }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil, url.user == nil else {
                    self.status.stringValue = "This share has no valid website address."
                    return
                }
                self.sharedURL = url
                self.status.stringValue = self.sharedTitle.isEmpty ? url.absoluteString : self.sharedTitle
                self.saveButton.isEnabled = true
            }
        }
    }

    @objc private func save() {
        guard let sharedURL,
              let root = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.dev.aether.browser") else {
            status.stringValue = "Aether’s shared storage is unavailable."
            return
        }
        let directory = root.appendingPathComponent("Incoming", isDirectory: true)
        let record = SharedLinkRecord(title: sharedTitle, url: sharedURL.absoluteString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(record)
            let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
            try data.write(to: file, options: .atomic)
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            status.stringValue = "Could not save this website."
        }
    }
}

private struct SharedLinkRecord: Encodable {
    let title: String
    let url: String
}
