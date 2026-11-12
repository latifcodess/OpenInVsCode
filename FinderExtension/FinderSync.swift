import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {

    /// Éditeurs supportés, par ordre de préférence : bundle ID + schéma d'URL associé.
    private let editors: [(bundleID: String, scheme: String)] = [
        ("com.microsoft.VSCode", "vscode"),
        ("com.microsoft.VSCodeInsiders", "vscode-insiders"),
    ]

    override init() {
        super.init()
        // Surveille tout le disque pour que le menu apparaisse partout
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let action: Selector
        switch menuKind {
        case .contextualMenuForItems:
            action = #selector(openSelectedItems(_:))
        case .contextualMenuForContainer:
            action = #selector(openCurrentFolder(_:))
        default:
            return nil
        }

        let menu = NSMenu(title: "")
        let item = NSMenuItem(title: "Ouvrir avec VS Code", action: action, keyEquivalent: "")
        item.image = vscodeIcon()
        menu.addItem(item)
        return menu
    }

    // MARK: - Actions

    /// Clic droit sur un ou plusieurs éléments.
    @objc private func openSelectedItems(_ sender: AnyObject?) {
        let controller = FIFinderSyncController.default()
        var urls = controller.selectedItemURLs() ?? []
        if urls.isEmpty, let current = controller.targetedURL() {
            urls = [current]
        }
        open(urls)
    }

    /// Clic droit dans le vide d'une fenêtre : ouvre le dossier affiché.
    @objc private func openCurrentFolder(_ sender: AnyObject?) {
        guard let current = FIFinderSyncController.default().targetedURL() else { return }
        open([current])
    }

    private func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        guard let editor = installedEditor() else {
            openWithURLScheme(urls, scheme: editors[0].scheme)
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: editor.appURL, configuration: config) { [weak self] _, error in
            guard let error else { return }
            NSLog("OpenInVSCode: ouverture directe échouée (\(error)), repli sur le schéma d'URL")
            DispatchQueue.main.async {
                self?.openWithURLScheme(urls, scheme: editor.scheme)
            }
        }
    }

    // Plan B : vscode://file/<chemin>
    private func openWithURLScheme(_ urls: [URL], scheme: String) {
        for url in urls {
            guard let path = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let schemeURL = URL(string: "\(scheme)://file\(path)") else { continue }
            NSWorkspace.shared.open(schemeURL)
        }
    }

    // MARK: - Helpers

    private func installedEditor() -> (appURL: URL, scheme: String)? {
        for editor in editors {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleID) {
                return (url, editor.scheme)
            }
        }
        return nil
    }

    private func vscodeIcon() -> NSImage? {
        guard let appURL = installedEditor()?.appURL else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
