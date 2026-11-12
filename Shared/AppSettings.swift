import AppKit

/// Réglages partagés entre l'app et l'extension Finder (via l'App Group).
enum AppSettings {
    static let appGroup = "79W4JUNG7Y.ch.latifcodess.OpenInVSCode"
    static let defaults = UserDefaults(suiteName: appGroup) ?? .standard

    enum Key {
        static let editor = "editor"
        static let newWindow = "newWindow"
        static let fileOpensParent = "fileOpensParent"
        static let showMenuIcon = "showMenuIcon"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let skippedVersion = "skippedVersion"
    }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.editor: Editor.automatic.rawValue,
            Key.newWindow: false,
            Key.fileOpensParent: false,
            Key.showMenuIcon: true,
            Key.autoCheckUpdates: true,
        ])
    }

    static var editor: Editor {
        Editor(rawValue: defaults.string(forKey: Key.editor) ?? "") ?? .automatic
    }
    static var newWindow: Bool { defaults.bool(forKey: Key.newWindow) }
    static var fileOpensParent: Bool { defaults.bool(forKey: Key.fileOpensParent) }
    static var showMenuIcon: Bool { defaults.object(forKey: Key.showMenuIcon) as? Bool ?? true }
}

/// Éditeurs compatibles avec le schéma d'URL `<scheme>://file/<chemin>` (VS Code et ses dérivés).
enum Editor: String, CaseIterable, Identifiable {
    case automatic, vscode, insiders, cursor, vscodium

    var id: String { rawValue }

    /// Ordre de recherche en mode automatique.
    static let concrete: [Editor] = [.vscode, .insiders, .cursor, .vscodium]

    var displayName: String {
        switch self {
        case .automatic: return "Automatique"
        case .vscode: return "VS Code"
        case .insiders: return "VS Code Insiders"
        case .cursor: return "Cursor"
        case .vscodium: return "VSCodium"
        }
    }

    var bundleID: String? {
        switch self {
        case .automatic: return nil
        case .vscode: return "com.microsoft.VSCode"
        case .insiders: return "com.microsoft.VSCodeInsiders"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .vscodium: return "com.vscodium"
        }
    }

    var urlScheme: String {
        switch self {
        case .automatic, .vscode: return "vscode"
        case .insiders: return "vscode-insiders"
        case .cursor: return "cursor"
        case .vscodium: return "vscodium"
        }
    }

    var appURL: URL? {
        bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    var isInstalled: Bool { appURL != nil }

    /// Éditeur réellement utilisé : en automatique, le premier installé (VS Code par défaut).
    var resolved: Editor {
        guard self == .automatic else { return self }
        return Editor.concrete.first(where: \.isInstalled) ?? .vscode
    }
}
