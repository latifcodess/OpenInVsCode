import SwiftUI
import FinderSync

@main
struct OpenInVSCodeApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Text("Open in VS Code").font(.title2).bold()
                Text("Active l'extension Finder pour voir « Ouvrir avec VS Code » dans le clic droit.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Activer l'extension…") {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(32)
            .frame(width: 380)
        }
        .windowResizability(.contentSize)
    }
}
