import AppKit
import SwiftUI

@main
struct BetterBrightnessApp: App {
    @StateObject private var controller = BrightnessController()

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
        }

        Settings {
            SettingsView(configurationStore: controller.configurationStore)
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var controller: BrightnessController
    @Environment(\.openSettings) private var openSettings

    init(controller: BrightnessController) {
        self.controller = controller
    }

    var body: some View {
        Button(
            controller.isPaused ? "Resume" : "Pause",
            systemImage: controller.isPaused ? "play.fill" : "pause.fill"
        ) {
            controller.togglePause()
        }

        Button("Settings", systemImage: "gearshape") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        }

        Divider()

        Button("Quit BetterBrightness", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
    }
}
