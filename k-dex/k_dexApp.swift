import AppKit
import SwiftUI

/// Scene-independent termination hook: `willTerminateNotification` observers
/// attached to a window scene are skipped when the user closes all windows
/// and then quits, and view-scoped streamers are unreachable by then. The
/// reaper knows every long-lived child (logs, watches, port forwards).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        ProcessReaper.shared.terminateAll()
    }
}

@main
struct KubeCompassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var portForwards = PortForwardManager()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(portForwards)
                .frame(minWidth: 980, minHeight: 580)
        }
        .commands {
            // View → Hide/Show Sidebar (⌃⌘S), absent by default in a
            // NavigationSplitView app unless explicitly requested.
            SidebarCommands()
            CommandGroup(after: .toolbar) {
                // On the cluster picker, refresh means "re-read the
                // kubeconfig" — requestRefresh() is a no-op before connect,
                // which read as ⌘R doing nothing on that screen.
                Button("Refresh") {
                    if case .ready = model.bootState {
                        model.requestRefresh()
                    } else {
                        Task { await model.reloadContexts() }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
