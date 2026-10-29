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

        subscription.cancel()
        try store.save(displayID: 3, lights: [light])
        var drafts = [LightDraft(configuration: light)]
        let collectionSubscription = store.$configuration.dropFirst().sink { configuration in
            LightDraft.mergeDiscoveryChanges(configuration.lights, into: &drafts)
        }
        defer { collectionSubscription.cancel() }
        drafts[0].ip = " 192.0.2.99 "
        drafts[0].name = "Edited destination"
        drafts[0].monitorMin = 25
        drafts[0].isEnabled = true
        let destination = DiscoveredWiZLight(
            macAddress: "001122334455", ipAddress: "192.0.2.99",
            deviceInfo: WiZDeviceInfo(moduleName: "Destination")
        )
        _ = try store.applyDiscoveryResults([destination])
        precondition(drafts.count == 1, "Discovery at an edited destination must not add a duplicate draft")
        // A later publication must not reintroduce the discovered row or lose the edit.
        _ = try store.applyDiscoveryResults([discovered, destination])
        precondition(drafts.count == 1 && drafts[0].id == light.id)
        precondition(drafts[0].name == "Edited destination" && drafts[0].monitorMin == 25 && drafts[0].isEnabled)
        try store.save(displayID: 3, lights: LightDraft.configurationsForSaving(drafts))
        precondition(store.configuration.lights.count == 1)
        let destinationSaved = store.configuration.lights[0]
        precondition(destinationSaved.id == light.id && destinationSaved.ip == "192.0.2.99")
        precondition(destinationSaved.macAddress == destination.macAddress)
        precondition(destinationSaved.deviceInfo?.moduleName == "Destination")
        precondition(drafts[0].macAddress == destination.macAddress)
        print("PASS: discovery at an edited destination reconciles identity and saves without duplicate IPs")

        _ = try store.applyDiscoveryResults([
            DiscoveredWiZLight(macAddress: destination.macAddress, ipAddress: "192.0.2.50",
                               deviceInfo: WiZDeviceInfo())
        ])
        precondition(drafts.count == 1 && drafts[0].ip == "192.0.2.50")
        precondition(drafts[0].name == "Edited destination" && drafts[0].monitorMin == 25 && drafts[0].isEnabled)
        print("PASS: a reconciled destination follows subsequent MAC address updates")

        collectionSubscription.cancel()
        try store.save(displayID: 3, lights: [light])
        drafts = [LightDraft(configuration: light)]
        drafts[0].ip = destination.ipAddress
        _ = try store.applyDiscoveryResults([destination])
        LightDraft.mergeDiscoveryChanges(store.configuration.lights, into: &drafts)
        precondition(drafts.count == 1)
        drafts[0].ip = "192.0.2.98"
        try store.save(displayID: 3, lights: LightDraft.configurationsForSaving(drafts))
        precondition(store.configuration.lights.count == 2)
        let movedManual = store.configuration.lights.first { $0.id == light.id }!
        precondition(movedManual.ip == "192.0.2.98" && movedManual.macAddress == nil && movedManual.deviceInfo == nil)
        precondition(store.configuration.lights.contains {
            $0.ip == destination.ipAddress && $0.macAddress == destination.macAddress
        })
        print("PASS: editing away from a discovered destination retains the light without attaching stale identity")
    }
}
