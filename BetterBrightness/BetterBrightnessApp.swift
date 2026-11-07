import AppKit
import SwiftUI

@main
struct BetterBrightnessApp: App {
    @StateObject private var controller = BrightnessController()
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(controller: controller)
        } label: {
            Label(
                "BetterBrightness",
                systemImage: controller.isPaused
                    ? "sun.max"
                    : "sun.max.fill"
            )
#if DEBUG
            .background { SettingsPreviewLauncher() }
#endif
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                configurationStore: controller.configurationStore,
                discovery: controller.discoveryController,
                launchAtLogin: launchAtLogin
            )
                .frame(minWidth: 740, minHeight: 560)
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)
    }
}

#if DEBUG
/// Allows an isolated UI preview to open Settings immediately after launch.
private struct SettingsPreviewLauncher: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.task {
            guard ProcessInfo.processInfo.arguments.contains("--preview-settings") else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        }
    }
}
#endif

private struct MenuBarContent: View {
    @ObservedObject var controller: BrightnessController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(
                controller.isPaused ? "Resume" : "Pause",
                systemImage: controller.isPaused ? "play.fill" : "pause.fill"
            ) {
                controller.togglePause()
            }

            Divider()

            Button("Settings…", systemImage: "gearshape") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }

            Button("Quit BetterBrightness", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .padding(14)
        .frame(width: 290, alignment: .leading)
    }
}
