import Combine
import Foundation

enum LightDraftTests {
    @MainActor
    static func run() throws {
        let suite = "BetterBrightness.LightDraftTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ConfigurationStore(defaults: defaults)
        // Preserve compatibility with a saved light from before discovery-only setup.
        let legacy = LightConfiguration(
            name: "Desk", ip: "192.0.2.10", isEnabled: false,
            mapping: BrightnessMapping(monitorMin: 40, monitorMax: 80,
                                       lightMinPercent: 1, lightMaxPercent: 100)
        )
        try store.save(displayID: 3, lights: [legacy])
        var drafts = [LightDraft(configuration: legacy)]
        let subscription = store.$configuration.dropFirst().sink { configuration in
            LightDraft.mergeDiscoveryChanges(configuration.lights, into: &drafts)
        }
        defer { subscription.cancel() }
        drafts[0].name = "Editing name"
        drafts[0].monitorMin = 25
        drafts[0].isEnabled = true
        _ = try store.applyDiscoveryResults([])
        precondition(drafts.count == 1 && drafts[0].ip == legacy.ip)
        precondition(drafts[0].name == "Editing name" && drafts[0].monitorMin == 25)
        print("PASS: zero replies preserve saved lights and pending detail edits")

        _ = try store.applyDiscoveryResults([
            DiscoveredWiZLight(macAddress: "aabbccddeeff", ipAddress: legacy.ip,
                               deviceInfo: WiZDeviceInfo(moduleName: "Module"))
        ])
        precondition(drafts.count == 1 && drafts[0].id == legacy.id)
        precondition(drafts[0].macAddress == "aabbccddeeff")
        precondition(drafts[0].deviceInfo?.moduleName == "Module")
        print("PASS: discovery identifies a legacy light without duplicating or renaming it")

        let replies = [
            DiscoveredWiZLight(macAddress: "aabbccddeeff", ipAddress: "192.0.2.50",
                               deviceInfo: WiZDeviceInfo()),
            DiscoveredWiZLight(macAddress: "001122334455", ipAddress: "192.0.2.99",
                               deviceInfo: WiZDeviceInfo())
        ]
        _ = try store.applyDiscoveryResults(replies)
        _ = try store.applyDiscoveryResults(replies.reversed())
        precondition(drafts.count == 2)
        precondition(drafts[0].ip == "192.0.2.50" && drafts[0].isIPAddressVerified)
        precondition(drafts[0].name == "Editing name" && drafts[0].monitorMin == 25 && drafts[0].isEnabled)
        precondition(drafts[1].macAddress == "001122334455" && drafts[1].name == "Light 1")
        try store.save(displayID: 3, lights: drafts.map(\.configuration))
        let reloaded = ConfigurationStore(defaults: defaults)
        precondition(reloaded.configuration.lights.count == 2)
        precondition(reloaded.configuration.lights[0].name == "Editing name")
        precondition(reloaded.configuration.lights[0].ip == "192.0.2.50")
        print("PASS: discovery merges DHCP updates and new lights while preserving and saving pending edits")
    }
}
