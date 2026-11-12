import SwiftUI
import FinderSync

struct SettingsView: View {
    @ObservedObject private var updates = UpdateManager.shared

    @AppStorage(AppSettings.Key.editor, store: AppSettings.defaults) private var editorRaw = Editor.automatic.rawValue
    @AppStorage(AppSettings.Key.newWindow, store: AppSettings.defaults) private var newWindow = false
    @AppStorage(AppSettings.Key.fileOpensParent, store: AppSettings.defaults) private var fileOpensParent = false
    @AppStorage(AppSettings.Key.showMenuIcon, store: AppSettings.defaults) private var showMenuIcon = true
    @AppStorage(AppSettings.Key.autoCheckUpdates, store: AppSettings.defaults) private var autoCheckUpdates = true

    @State private var extensionEnabled = FIFinderSyncController.isExtensionEnabled
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.requiresApproval
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: extensionEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(extensionEnabled ? .green : .orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(extensionEnabled ? "Extension activée" : "Extension désactivée")
                        Text(extensionEnabled
                             ? "« Ouvrir avec \(selectedEditor.resolved.displayName) » est dans le clic droit du Finder."
                             : "Active-la pour voir l'option dans le clic droit du Finder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(extensionEnabled ? "Gérer…" : "Activer…") {
                        FIFinderSyncController.showExtensionManagementInterface()
                    }
                }
            } header: {
                Text("Extension Finder")
            } footer: {
                Text("Astuce : un bouton est aussi disponible pour la barre d'outils du Finder (clic droit sur la barre d'outils › Personnaliser la barre d'outils…).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ouverture") {
                Picker("Éditeur", selection: $editorRaw) {
                    ForEach(Editor.allCases) { editor in
                        Text(label(for: editor)).tag(editor.rawValue)
                    }
                }
                Toggle("Toujours ouvrir dans une nouvelle fenêtre", isOn: $newWindow)
                Toggle("Pour un fichier, ouvrir son dossier parent", isOn: $fileOpensParent)
                Toggle("Afficher l'icône de l'éditeur dans le menu", isOn: $showMenuIcon)
            }

            Section("Général") {
                Toggle("Ouvrir au démarrage de la session", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if loginNeedsApproval {
                    HStack {
                        Text("À autoriser dans les Réglages Système.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Ouvrir les réglages…") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Rechercher les mises à jour automatiquement", isOn: $autoCheckUpdates)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(updates.currentVersion)")
                        if let status = updates.status {
                            Text(status).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if updates.isChecking || updates.isInstalling {
                        ProgressView().controlSize(.small)
                    }
                    Button("Rechercher maintenant") {
                        Task { await updates.check(userInitiated: true) }
                    }
                    .disabled(updates.isChecking || updates.isInstalling)
                }
            } header: {
                Text("Mises à jour")
            } footer: {
                Text("La recherche automatique a lieu à chaque ouverture de l'app et, si l'ouverture au démarrage est activée, à chaque démarrage de la session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
    }

    private var selectedEditor: Editor { Editor(rawValue: editorRaw) ?? .automatic }

    private func label(for editor: Editor) -> String {
        if editor == .automatic {
            return "Automatique (\(Editor.automatic.resolved.displayName))"
        }
        return editor.isInstalled ? editor.displayName : "\(editor.displayName) — non installé"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            loginError = "Impossible de modifier l'ouverture au démarrage : \(error.localizedDescription)"
        }
        refreshStatus()
    }

    private func refreshStatus() {
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
        launchAtLogin = LoginItem.isEnabled || LoginItem.requiresApproval
        loginNeedsApproval = LoginItem.requiresApproval
    }
}
