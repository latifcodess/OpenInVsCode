import ServiceManagement

/// Ouverture au démarrage de la session, via un LaunchAgent embarqué dans l'app
/// (Contents/Library/LaunchAgents). L'agent lance l'app avec `--login` : elle vérifie
/// alors les mises à jour en arrière-plan, sans ouvrir de fenêtre, puis se ferme.
enum LoginItem {
    static let service = SMAppService.agent(plistName: "ch.latifcodess.OpenInVSCode.LoginAgent.plist")

    static var isEnabled: Bool { service.status == .enabled }
    static var requiresApproval: Bool { service.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
