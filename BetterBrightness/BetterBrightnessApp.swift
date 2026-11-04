import AppKit
import SwiftUI

@main
struct BetterBrightnessApp: App {
    @StateObject private var controller = BrightnessController()
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(controller: controller, launchAtLogin: launchAtLogin)
        } label: {
            Label(
                "BetterBrightness",
                systemImage: controller.isPaused
                    ? "sun.max"
                    : "sun.max.fill"
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                configurationStore: controller.configurationStore,
                launchAtLogin: launchAtLogin
            )
                .frame(minWidth: 740, minHeight: 560)
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var controller: BrightnessController
    @ObservedObject var launchAtLogin: LaunchAtLoginController
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

            DiscoveryMenuContent(discovery: controller.discoveryController)

            Divider()

            LaunchAtLoginControl(controller: launchAtLogin)

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

struct DiscoveryMenuContent: View {
    @ObservedObject var discovery: DiscoveryController

    var body: some View {
        Button("Discover Lights", systemImage: "dot.radiowaves.left.and.right") {
            discovery.discoverLights()
        }
        .disabled(discovery.isDiscovering)
        .buttonStyle(.bordered)

        if discovery.isDiscovering {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(discovery.attempt == 0
                     ? "Starting discovery…"
                     : "Attempt \(discovery.attempt) of \(discovery.totalAttempts)")
            }
        } else if let errorMessage = discovery.errorMessage {
            Text("Discovery failed")
            Text(errorMessage)
        } else if let summary = discovery.lastSummary {
            Text(summary.foundLights == 0
                 ? "No WiZ lights found"
                 : "\(summary.foundLights) \(summary.foundLights == 1 ? "light" : "lights") found")
            Text("\(summary.updatedIPs) IP \(summary.updatedIPs == 1 ? "address" : "addresses") updated")
            if summary.newLights > 0 {
                Text("\(summary.newLights) new · Enable in Settings")
            }
            if summary.invalidatedIPs > 0 {
                Text("\(summary.invalidatedIPs) waiting for rediscovery")
            }
        }
    }
}
