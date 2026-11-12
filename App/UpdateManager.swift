import AppKit
import Security

/// Une release GitHub (https://api.github.com/repos/<repo>/releases/latest).
struct Release: Decodable {
    let tagName: String
    let htmlURL: URL
    let body: String?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let downloadURL: URL
        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body, assets
    }

    var version: String { tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) }
    var zipAsset: Asset? { assets.first { $0.name.lowercased().hasSuffix(".zip") } }
}

enum UpdateError: LocalizedError {
    case noArchive, appNotFound, badSignature, network(Int)

    var errorDescription: String? {
        switch self {
        case .noArchive: return "La release ne contient pas d'archive .zip de l'app."
        case .appNotFound: return "L'archive téléchargée ne contient pas d'application."
        case .badSignature: return "La signature de l'app téléchargée ne correspond pas à celle de l'app installée."
        case .network(let code): return "GitHub a répondu avec le code HTTP \(code)."
        }
    }
}

/// Mises à jour via les releases GitHub du dépôt : vérification, téléchargement, remplacement de l'app et relance.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    static let repository = "latifcodess/OpenInVsCode"
    static let extensionID = "ch.latifcodess.OpenInVSCode.FinderExtension"

    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var status: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - Vérification

    /// - Parameter userInitiated: `true` quand l'utilisateur a cliqué sur « Rechercher » : on affiche aussi
    ///   « à jour » et les erreurs. En automatique, on reste silencieux sauf s'il y a une mise à jour
    ///   (et on respecte « Ignorer cette version »).
    func check(userInitiated: Bool) async {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            guard let release = try await fetchLatestRelease(),
                  Self.isVersion(release.version, newerThan: currentVersion) else {
                status = "Vous avez la dernière version (\(currentVersion))."
                if userInitiated { showInfo("Open in VS Code est à jour", status!) }
                return
            }
            status = "Version \(release.version) disponible."
            if !userInitiated, AppSettings.defaults.string(forKey: AppSettings.Key.skippedVersion) == release.version {
                return
            }
            await presentUpdateAlert(for: release)
        } catch {
            status = "Impossible de vérifier les mises à jour."
            if userInitiated { showInfo("Impossible de vérifier les mises à jour", error.localizedDescription) }
        }
    }

    private func fetchLatestRelease() async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OpenInVSCode-Updater", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }  // aucune release publiée
        guard code == 200 else { throw UpdateError.network(code) }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Alerte

    private func presentUpdateAlert(for release: Release) async {
        let alert = NSAlert()
        alert.messageText = "Une mise à jour est disponible"
        var info = "Open in VS Code \(release.version) est disponible. Vous avez la version \(currentVersion)."
        if let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            info += "\n\nNouveautés :\n" + String(notes.prefix(600))
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Installer et relancer")
        alert.addButton(withTitle: "Plus tard")
        alert.addButton(withTitle: "Ignorer cette version")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            await install(release)
        case .alertThirdButtonReturn:
            AppSettings.defaults.set(release.version, forKey: AppSettings.Key.skippedVersion)
        default:
            break
        }
    }

    // MARK: - Installation

    private func install(_ release: Release) async {
        isInstalling = true
        status = "Téléchargement de la version \(release.version)…"
        do {
            guard let asset = release.zipAsset else { throw UpdateError.noArchive }
            let newApp = try await downloadAndExtract(asset)
            guard Self.teamIdentifier(of: newApp) != nil,
                  Self.teamIdentifier(of: newApp) == Self.teamIdentifier(of: Bundle.main.bundleURL) else {
                throw UpdateError.badSignature
            }
            status = "Installation…"
            try replaceAndRelaunch(with: newApp)
            NSApp.terminate(nil)
        } catch {
            isInstalling = false
            status = "La mise à jour a échoué."
            let alert = NSAlert()
            alert.messageText = "La mise à jour a échoué"
            alert.informativeText = error.localizedDescription
                + "\n\nTu peux télécharger la nouvelle version manuellement depuis GitHub."
            alert.addButton(withTitle: "Ouvrir la page GitHub")
            alert.addButton(withTitle: "Annuler")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    private func downloadAndExtract(_ asset: Release.Asset) async throws -> URL {
        let (tmpFile, response) = try await URLSession.shared.download(from: asset.downloadURL)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UpdateError.network(code) }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenInVSCode-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let zip = workDir.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: tmpFile, to: zip)

        try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, workDir.appendingPathComponent("extracted").path])
        let extracted = workDir.appendingPathComponent("extracted")
        let items = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
        guard let app = items.first(where: { $0.pathExtension == "app" }) else { throw UpdateError.appNotFound }
        return app
    }

    /// Lance un script détaché (nouvelle session) qui attend la fin de l'app, remplace le bundle,
    /// réenregistre l'extension Finder et relance l'app.
    private func replaceAndRelaunch(with newApp: URL) throws {
        let script = """
        pid="$1"; new="$2"; dest="$3"; ext="$4"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        staging="${dest%.app}.updating.app"
        rm -rf "$staging"
        /usr/bin/ditto "$new" "$staging" || exit 1
        rm -rf "$dest" && mv "$staging" "$dest" || exit 1
        /usr/bin/xattr -dr com.apple.quarantine "$dest" 2>/dev/null
        /usr/bin/pluginkit -a "$dest/Contents/PlugIns/FinderExtension.appex"
        /usr/bin/pluginkit -e use -i "$ext"
        /usr/bin/killall Finder 2>/dev/null  # recharge l'extension (elle ne redémarre pas seule)
        /usr/bin/open "$dest"
        """
        let args = ["/bin/sh", "-c", script, "sh",
                    String(ProcessInfo.processInfo.processIdentifier),
                    newApp.path, Bundle.main.bundleURL.path, Self.extensionID]
        try Self.spawnDetached(args)
    }

    // MARK: - Utilitaires

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "OpenInVSCode", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(tool) a échoué (\(process.terminationStatus))."])
        }
    }

    /// posix_spawn avec POSIX_SPAWN_SETSID : le script survit à la fin de l'app (même lancée par launchd).
    private static func spawnDetached(_ args: [String]) throws {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, args[0], nil, &attr, &argv, environ)
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(result))
        }
    }

    /// Team ID de la signature d'un bundle, seulement si la signature est valide.
    static func teamIdentifier(of url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func showInfo(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
