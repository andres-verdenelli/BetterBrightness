import AppKit
import SwiftUI

@main
struct BetterBrightnessApp: App {
    @StateObject private var controller: BrightnessController
    private let isGroupPreview: Bool
    private let statusMenu: BrightnessStatusMenu

    init() {
#if DEBUG
        isGroupPreview = ProcessInfo.processInfo.arguments.contains("--group-preview")
#else
        isGroupPreview = false
#endif
#if DEBUG
        if isGroupPreview {
            let defaults = UserDefaults(suiteName: "andydev.BetterBrightness.groupsDemo.v1")!
            // Start every simulated UI session from the same review fixture.
            defaults.removeObject(forKey: "betterBrightness.configuration")
            let store = ConfigurationStore(defaults: defaults)
            do {
                let mapping = BrightnessMapping(monitorMin: 40, monitorMax: 80, lightMinPercent: 1, lightMaxPercent: 100)
                let lights = ["Sofa Lamp", "Reading Lamp", "TV Backlight", "Desk Lamp", "Bookshelf", "Kitchen Ceiling", "Hallway"].enumerated().map { index, name in
                    LightConfiguration(name: name, macAddress: String(format: "0200000000%02x", index),
                                       ip: "192.0.2.\(index + 10)", isEnabled: index == 0,
                                       mapping: index == 1 ? BrightnessMapping(monitorMin: 20, monitorMax: 90, lightMinPercent: 10, lightMaxPercent: 70) : mapping)
                }
                do {
                    try store.save(displayID: 3, lights: lights)
                    _ = try store.createGroup(name: "Living", memberIDs: [lights[0].id, lights[1].id, lights[2].id], sourceID: lights[0].id)
                    _ = try store.createGroup(name: "Office", memberIDs: [lights[3].id, lights[4].id], sourceID: lights[3].id)
                    var demoLights = store.configuration.lights
                    demoLights[5].showInMenu = true
                    demoLights[5].isEnabled = true
                    var demoGroups = store.configuration.groups
                    demoGroups[0].showInMenu = true
                    demoGroups[1].showInMenu = true
                    try store.save(displayID: 3, lights: demoLights, groups: demoGroups)
                }
                catch { assertionFailure("Could not prepare preview: \(error)") }
            }
            let controller = BrightnessController(configurationStore: store, startsServices: false)
            controller.sendBrightnessToEnabledLights(60)
            _controller = StateObject(wrappedValue: controller)
            statusMenu = BrightnessStatusMenu(controller: controller)
        } else {
            let controller = BrightnessController()
            _controller = StateObject(wrappedValue: controller)
            statusMenu = BrightnessStatusMenu(controller: controller)
        }
#else
        let controller = BrightnessController()
        _controller = StateObject(wrappedValue: controller)
        statusMenu = BrightnessStatusMenu(controller: controller)
#endif
    }
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    private var previewMenuAction: (() -> Void)? {
#if DEBUG
        isGroupPreview ? { statusMenu.showPreviewMenu() } : nil
#else
        nil
#endif
    }

    var body: some Scene {
#if DEBUG
        Window("Diagnostics", id: "debug-diagnostics") {
            DebugDiagnosticsView(controller: controller, store: controller.configurationStore, simulated: isGroupPreview)
        }
        .defaultSize(width: 520, height: 460)
        .defaultLaunchBehavior(.suppressed)
        Window("BetterBrightness Preview", id: "preview-launcher") {
            StartupSettingsLauncher().frame(width: 240, height: 100)
        }
        .defaultSize(width: 240, height: 100)
        .defaultLaunchBehavior(ProcessInfo.processInfo.arguments.contains("--preview-settings") ? .presented : .suppressed)
#endif
        Settings {
            SettingsView(
                configurationStore: controller.configurationStore,
                discovery: controller.discoveryController,
                launchAtLogin: launchAtLogin,
                previewMenu: previewMenuAction
            )
                .environment(\.isGroupPreview, isGroupPreview)

                .frame(minWidth: 740, minHeight: 560)
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)
    }
}

private struct StartupSettingsLauncher: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Color.clear.task {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-settings") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }
#endif
            dismiss()
        }
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
