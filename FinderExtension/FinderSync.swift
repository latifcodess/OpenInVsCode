import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {

    override init() {
        super.init()
        AppSettings.registerDefaults()
        // Surveille tout le disque pour que le menu apparaisse partout
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - Bouton de barre d'outils (Présentation › Personnaliser la barre d'outils…)

    override var toolbarItemName: String { "Ouvrir dans l'éditeur" }
    override var toolbarItemToolTip: String { "Ouvrir le dossier courant ou la sélection dans l'éditeur" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)
            ?? NSImage(named: NSImage.folderName)!
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let action: Selector
        switch menuKind {
        case .contextualMenuForItems, .toolbarItemMenu:
            action = #selector(openSelectedItems(_:))
        case .contextualMenuForContainer:
            action = #selector(openCurrentFolder(_:))
        default:
            return nil
        }

        let editor = AppSettings.editor.resolved
        let menu = NSMenu(title: "")
        let item = NSMenuItem(title: "Ouvrir avec \(editor.displayName)", action: action, keyEquivalent: "")
        if AppSettings.showMenuIcon {
            item.image = icon(for: editor)
        }
        menu.addItem(item)
        return menu
    }

    // MARK: - Actions

    /// Clic droit sur un ou plusieurs éléments (ou bouton de barre d'outils).
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

    /// Passe par le schéma d'URL `<scheme>://file/<chemin>` plutôt que NSWorkspace.open(urls, withApplicationAt:) :
    /// l'extension est sandboxée et n'a pas accès aux fichiers, donc l'ouverture directe déclenche
    /// l'alerte « … n'est pas autorisé à ouvrir … ». Le schéma d'URL ne transmet qu'un chemin, sans accès requis.
    private func open(_ urls: [URL]) {
        var targets: [URL] = []
        for url in urls {
            let target = (AppSettings.fileOpensParent && !isDirectory(url)) ? url.deletingLastPathComponent() : url
            if !targets.contains(where: { $0.standardizedFileURL.path == target.standardizedFileURL.path }) {
                targets.append(target)
            }
        }

        let scheme = AppSettings.editor.resolved.urlScheme
        let query = AppSettings.newWindow ? "?windowId=_blank" : ""
        for url in targets {
            guard let path = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let schemeURL = URL(string: "\(scheme)://file\(path)\(query)") else { continue }
            NSWorkspace.shared.open(schemeURL)
        }
    }

    // MARK: - Helpers

    private func isDirectory(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return true }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func icon(for editor: Editor) -> NSImage? {
        guard let appURL = editor.appURL else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
