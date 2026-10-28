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

        try LightDraftTests.run()
    }
}
