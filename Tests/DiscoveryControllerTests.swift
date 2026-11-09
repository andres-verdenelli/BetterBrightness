import Foundation

@main
struct DiscoveryControllerTests {
    @MainActor
    static func main() throws {
        let suite = "BetterBrightness.DiscoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ConfigurationStore(defaults: defaults)
        let light = LightConfiguration(
            name: "Desk", macAddress: "aabbccddeeff", ip: "192.0.2.10",
            isEnabled: true,
            mapping: BrightnessMapping(monitorMin: 30, monitorMax: 75,
                                       lightMinPercent: 5, lightMaxPercent: 90)
        )
        try store.save(displayID: 3, lights: [light])

        var starts = 0
        var reportAttempt: ((Int) -> Void)?
        var finish: ((Result<[DiscoveredWiZLight], Error>) -> Void)?
        let discovery = DiscoveryController(configurationStore: store) { configuration, attempt, completion in
            starts += 1
            precondition(configuration.attemptCount == 3)
            reportAttempt = attempt
            finish = completion
        }

        // No Settings view is constructed: discovery must have its own lifetime.
        discovery.discoverLights()
        precondition(discovery.isDiscovering && discovery.lastSummary == nil)
        reportAttempt?(2)
        precondition(discovery.attempt == 2 && discovery.totalAttempts == 3)
        discovery.discoverLights()
        precondition(starts == 1, "Concurrent requests must not start a second scan")
        print("PASS: progress and overlapping requests")

        finish?(.success([
            DiscoveredWiZLight(macAddress: "aabbccddeeff", ipAddress: "192.0.2.20",
                               deviceInfo: WiZDeviceInfo()),
            DiscoveredWiZLight(macAddress: "001122334455", ipAddress: "192.0.2.30",
                               deviceInfo: WiZDeviceInfo())
        ]))
        precondition(!discovery.isDiscovering && discovery.errorMessage == nil)
        precondition(discovery.lastSummary?.foundLights == 2)
        precondition(discovery.lastSummary?.updatedIPs == 1)
        precondition(discovery.lastSummary?.newLights == 1)
        let saved = store.configuration.lights.first { $0.id == light.id }!
        precondition(saved.ip == "192.0.2.20")
        precondition(saved.name == "Desk" && saved.isEnabled)
        precondition(saved.mapping.monitorMin == 30 && saved.mapping.lightMaxPercent == 90)
        precondition(store.configuration.lights.last?.isEnabled == false)
        let reloaded = ConfigurationStore(defaults: defaults)
        precondition(reloaded.configuration.lights.first?.ip == "192.0.2.20")
        print("PASS: results persist without Settings, preserving names, ranges and enabled state")

        discovery.discoverLights()
        precondition(discovery.lastSummary == nil && discovery.errorMessage == nil)
        finish?(.failure(WiZDiscoveryError.couldNotSendBroadcast("Test failure")))
        precondition(!discovery.isDiscovering && discovery.errorMessage != nil)
        precondition(discovery.lastSummary == nil)
        print("PASS: failure clears obsolete results and ends progress")

        discovery.discoverLights()
        precondition(discovery.errorMessage == nil)
        finish?(.success([]))
        precondition(!discovery.isDiscovering && discovery.lastSummary?.foundLights == 0)
        precondition(discovery.lastSummary?.updatedIPs == 0)
        precondition(store.configuration.lights.count == 2)
        print("PASS: retry and zero replies keep saved lights")

        discovery.discoverLights()
        finish?(.success([
            DiscoveredWiZLight(macAddress: "aabbccddeeff", ipAddress: "192.0.2.50",
                               deviceInfo: WiZDeviceInfo()),
            DiscoveredWiZLight(macAddress: "001122334455", ipAddress: "192.0.2.50",
                               deviceInfo: WiZDeviceInfo())
        ]))
        precondition(!discovery.isDiscovering && discovery.errorMessage != nil)
        precondition(discovery.lastSummary == nil)
        precondition(store.configuration.lights.first?.ip == "192.0.2.20")
        print("PASS: save failures surface without partially applying discovery")

        try testDiscoveryOnly()
        try testNumberedNames()
        try LightDraftTests.run()
        try LightGroupTests.run()
        try MenuOffsetTests.run()
    }
    @MainActor
    private static func testDiscoveryOnly() throws {
        let suite = "BetterBrightness.DiscoveryOnlyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ConfigurationStore(defaults: defaults)
        precondition(store.configuration.lights.isEmpty && store.configuration.nextLightNumber == 1)
        try store.save(displayID: 5, lights: [], discovery: .standard)
        precondition(ConfigurationStore(defaults: defaults).configuration.monitor.displayID == 5)
        _ = try store.applyDiscoveryResults([])
        precondition(store.configuration.lights.isEmpty && store.configuration.nextLightNumber == 1)
        let reply = DiscoveredWiZLight(macAddress: "aabbccddeeff", ipAddress: "192.0.2.10",
                                      deviceInfo: WiZDeviceInfo())
        _ = try store.applyDiscoveryResults([reply])
        precondition(store.configuration.lights.count == 1)
        precondition(store.configuration.lights[0].name == "Light 1")
        precondition(store.configuration.lights[0].macAddress == reply.macAddress)
        precondition(!store.configuration.lights[0].isEnabled)
        try store.save(displayID: 5, lights: [])
        let reloaded = ConfigurationStore(defaults: defaults)
        precondition(reloaded.configuration.lights.isEmpty && reloaded.configuration.nextLightNumber == 2)
        _ = try reloaded.applyDiscoveryResults([reply])
        precondition(reloaded.configuration.lights[0].name == "Light 2")
        print("PASS: fresh installation and zero replies add no lights; settings and last-light removal support an empty list")
    }

    @MainActor
    private static func testNumberedNames() throws {
        let suite = "BetterBrightness.NumberingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func light(_ name: String, _ ip: String) -> LightConfiguration {
            LightConfiguration(name: name, ip: ip, isEnabled: false,
                mapping: BrightnessMapping(monitorMin: 40, monitorMax: 80,
                                          lightMinPercent: 1, lightMaxPercent: 100))
        }
        let legacy = AppConfiguration(monitor: MonitorConfiguration(displayID: 3), lights: [
            light("Desk", "192.0.2.1"), light("ESP25_SHRGB_01", "192.0.2.2"),
            light("Light 7", "192.0.2.3")
        ])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        json.removeValue(forKey: "nextLightNumber")
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "betterBrightness.configuration")
        let store = ConfigurationStore(defaults: defaults)
        precondition(store.configuration.nextLightNumber == 8)
        precondition(store.configuration.lights.map(\.name) == ["Desk", "ESP25_SHRGB_01", "Light 7"])
        let empty = AppConfiguration(monitor: MonitorConfiguration(displayID: 3), lights: [])
        precondition(empty.nextLightNumber == 1)
        print("PASS: legacy configuration infers numbering and preserves existing names")

        let discovered = [
            DiscoveredWiZLight(macAddress: "aabbccddee02", ipAddress: "192.0.2.12",
                               deviceInfo: WiZDeviceInfo(moduleName: "ESP25_SHRGB_01")),
            DiscoveredWiZLight(macAddress: "aabbccddee01", ipAddress: "192.0.2.11",
                               deviceInfo: WiZDeviceInfo())
        ]
        _ = try store.applyDiscoveryResults(discovered)
        precondition(store.configuration.lights.suffix(2).map(\.name) == ["Light 8", "Light 9"])
        precondition(store.configuration.lights.last?.deviceInfo?.moduleName == "ESP25_SHRGB_01")
        precondition(store.configuration.nextLightNumber == 10)
        _ = try store.applyDiscoveryResults(discovered.reversed())
        precondition(store.configuration.nextLightNumber == 10 && store.configuration.lights.count == 5)
        print("PASS: discoveries receive sequential names ordered by MAC, not response order")

        var changed = store.configuration.lights
        changed[3].name = "Kitchen"
        changed.removeLast()
        try store.save(displayID: 3, lights: changed)
        let reloaded = ConfigurationStore(defaults: defaults)
        _ = try reloaded.applyDiscoveryResults([discovered[0]])
        precondition(reloaded.configuration.lights.last?.name == "Light 10")
        var collision = reloaded.configuration.lights
        collision[0].name = "Light 12"
        try reloaded.save(displayID: 3, lights: collision)
        _ = try reloaded.applyDiscoveryResults([
            DiscoveredWiZLight(macAddress: "aabbccddee03", ipAddress: "192.0.2.13",
                               deviceInfo: WiZDeviceInfo())
        ])
        precondition(reloaded.configuration.lights.last?.name == "Light 13")
        let counter = reloaded.configuration.nextLightNumber
        do {
            _ = try reloaded.applyDiscoveryResults([
                discovered[0],
                DiscoveredWiZLight(macAddress: "aabbccddee03", ipAddress: discovered[0].ipAddress,
                                   deviceInfo: WiZDeviceInfo())
            ])
            preconditionFailure("Conflicting discovery should fail")
        } catch ConfigurationError.conflictingDiscoveryIPAddress { }
        precondition(reloaded.configuration.nextLightNumber == counter)
        precondition(ConfigurationStore(defaults: defaults).configuration.nextLightNumber == counter)
        print("PASS: rename, deletion and restart preserve numbering; collisions skip and failed discovery consumes nothing")
    }

}
