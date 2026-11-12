import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    /// Lancée par le LaunchAgent au démarrage de la session (voir LoginItem).
    private let isLoginLaunch = CommandLine.arguments.contains("--login")
    /// L'utilisateur a ouvert la fenêtre pendant que l'instance « démarrage » tournait.
    private var userOpenedWindow = false

    private var autoCheck: Bool { AppSettings.defaults.bool(forKey: AppSettings.Key.autoCheckUpdates) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        NSApp.mainMenu = makeMainMenu()

        if isLoginLaunch {
            // Démarrage de session : pas de fenêtre ni d'icône dans le Dock, juste la vérification.
            NSApp.setActivationPolicy(.accessory)
            Task {
                if autoCheck { await UpdateManager.shared.check(userInitiated: false) }
                if !userOpenedWindow { NSApp.terminate(nil) }
            }
        } else {
            showSettings()
            if autoCheck {
                Task { await UpdateManager.shared.check(userInitiated: false) }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !isLoginLaunch || userOpenedWindow
    }

    // MARK: - Fenêtre

    @objc func showSettings() {
        userOpenedWindow = true
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Open in VS Code"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        Task { await UpdateManager.shared.check(userInitiated: true) }
    }

    // MARK: - Menu

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "À propos de Open in VS Code",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Rechercher les mises à jour…", action: #selector(checkForUpdates), keyEquivalent: "")
            .target = self
        appMenu.addItem(withTitle: "Réglages…", action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Masquer Open in VS Code", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quitter Open in VS Code", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Fenêtre")
        windowMenu.addItem(withTitle: "Fermer", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Placer dans le Dock", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        return main
    }
}
