import SwiftUI
import AppKit
import CadenceCore

/// Opens the database before anything is drawn.
///
/// If the file cannot be opened the application says so plainly instead of falling
/// back to memory: silently accepting a day's work that will vanish would be the
/// worst possible failure mode for this product.
@MainActor
final class AppBootstrap: ObservableObject {
    enum State {
        case loading
        case ready(AppModel)
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    var model: AppModel? {
        if case .ready(let model) = state { return model }
        return nil
    }

    func start() {
        state = .loading
        do {
            let store = try CadenceStore.open(at: CadenceStore.defaultFileURL())
            state = .ready(AppModel(store: store))
        } catch {
            state = .failed(AppModel.humanMessage(for: error))
        }
    }

    /// Swaps the live database for a snapshot and rebuilds the whole model around
    /// it. No restart is needed because nothing outside the model holds the store.
    func restore(from snapshot: URL) throws {
        model?.store.close()
        state = .loading
        try BackupManager.restore(from: snapshot, replacing: CadenceStore.defaultFileURL())
        start()
        model?.showToast("Sauvegarde restaurée", undoLabel: nil)
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([CadenceStore.defaultDirectory()])
    }
}

final class CadenceAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(CadenceAppDelegate.self) private var delegate
    @StateObject private var bootstrap = AppBootstrap()

    var body: some Scene {
        Window("Cadence", id: "cadence.main") {
            RootView()
                .environmentObject(bootstrap)
                .frame(
                    minWidth: Metrics.minimumWindow.width,
                    minHeight: Metrics.minimumWindow.height
                )
                .task {
                    if case .loading = bootstrap.state { bootstrap.start() }
                }
        }
        .defaultSize(width: Metrics.preferredWindow.width, height: Metrics.preferredWindow.height)
        .commands { CadenceCommands(bootstrap: bootstrap) }
    }
}
