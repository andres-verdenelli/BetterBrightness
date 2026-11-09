import AppKit
import SwiftUI

@main
struct BetterBrightnessApp: App {
    @StateObject private var controller: BrightnessController
    private let isGroupPreview: Bool

    init() {
#if DEBUG
        isGroupPreview = ProcessInfo.processInfo.arguments.contains("--group-preview")
#else
        isGroupPreview = false
#endif
        if isGroupPreview {
            let defaults = UserDefaults(suiteName: "andydev.BetterBrightness.groupsDemo.v1")!
            let store = ConfigurationStore(defaults: defaults)
            if defaults.data(forKey: "betterBrightness.configuration") == nil {
                let mapping = BrightnessMapping(monitorMin: 40, monitorMax: 80, lightMinPercent: 1, lightMaxPercent: 100)
                let lights = ["Desk", "Floor", "Shelf", "Window"].enumerated().map { index, name in
                    LightConfiguration(name: name, macAddress: String(format: "0200000000%02x", index),
                                       ip: "192.0.2.\(index + 10)", isEnabled: index == 0,
                                       mapping: index == 1 ? BrightnessMapping(monitorMin: 20, monitorMax: 90, lightMinPercent: 10, lightMaxPercent: 70) : mapping)
                }
                do {
                    try store.save(displayID: 3, lights: lights)
                    _ = try store.createGroup(name: "Studio", memberIDs: [lights[2].id, lights[3].id], sourceID: lights[2].id)
                }
                catch { assertionFailure("Could not prepare preview: \(error)") }
            }
            _controller = StateObject(wrappedValue: BrightnessController(configurationStore: store, startsServices: false))
        } else {
            _controller = StateObject(wrappedValue: BrightnessController())
        }
    }
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
                .environment(\.isGroupPreview, isGroupPreview)
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
private struct GroupPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isGroupPreview: Bool {
        get { self[GroupPreviewKey.self] }
        set { self[GroupPreviewKey.self] = newValue }
    }
}
