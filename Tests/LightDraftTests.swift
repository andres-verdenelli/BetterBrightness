import Combine
import Foundation

enum LightDraftTests {
    @MainActor
    static func run() throws {
        let suite = "BetterBrightness.LightDraftTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ConfigurationStore(defaults: defaults)
        let light = LightConfiguration(
            name: "Manual", ip: "192.0.2.10", isEnabled: false,
            mapping: BrightnessMapping(monitorMin: 40, monitorMax: 80,
                                       lightMinPercent: 1, lightMaxPercent: 100)
        )
        try store.save(displayID: 3, lights: [light])
        var draft = LightDraft(configuration: light)
        let subscription = store.$configuration.dropFirst().sink { configuration in
            if let saved = configuration.lights.first(where: { $0.id == draft.id }) {
                draft.mergeDiscoveryChanges(saved)
            }
        }
        defer { subscription.cancel() }

        draft.ip = "192.0.2.99"
        _ = try store.applyDiscoveryResults([])
        precondition(draft.ip == "192.0.2.99", "Zero replies must preserve the manual IP edit")
        precondition(store.configuration.lights[0].ip == "192.0.2.10")
        print("PASS: zero-reply discovery preserves an unsaved manual IP")

        // A reply from the old address must not attach its identity to the new draft address.
        draft.name = "Editing name"
        draft.monitorMin = 25
        draft.isEnabled = true
        let discovered = DiscoveredWiZLight(
            macAddress: "aabbccddeeff", ipAddress: "192.0.2.10",
            deviceInfo: WiZDeviceInfo(moduleName: "Old address")
        )
        _ = try store.applyDiscoveryResults([discovered])
        precondition(draft.ip == "192.0.2.99" && draft.macAddress == nil)
        precondition(draft.deviceInfo == nil)
        precondition(draft.name == "Editing name" && draft.monitorMin == 25 && draft.isEnabled)
        precondition(store.configuration.lights[0].macAddress == "aabbccddeeff")
        print("PASS: discovery at the old IP does not overwrite or identify the manual edit")

        // Saving advances the baseline so later discovery can identify the edited address.
        try store.save(displayID: 3, lights: [draft.configuration])
        let reloaded = ConfigurationStore(defaults: defaults)
        precondition(reloaded.configuration.lights[0].ip == "192.0.2.99")
        _ = try store.applyDiscoveryResults([
            DiscoveredWiZLight(macAddress: "001122334455", ipAddress: "192.0.2.99",
                               deviceInfo: WiZDeviceInfo(moduleName: "New address"))
        ])
        precondition(draft.macAddress == "001122334455")
        precondition(draft.deviceInfo?.moduleName == "New address")
        print("PASS: saving a manual IP persists it and allows subsequent identification")

        _ = try store.applyDiscoveryResults([
            DiscoveredWiZLight(macAddress: "001122334455", ipAddress: "192.0.2.50",
                               deviceInfo: WiZDeviceInfo())
        ])
        precondition(draft.ip == "192.0.2.50" && draft.isIPAddressVerified)
        precondition(draft.name == "Editing name" && draft.monitorMin == 25 && draft.isEnabled)
        print("PASS: known MAC address updates still merge without replacing other edits")
    }
}
