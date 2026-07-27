import Combine
import Foundation
import Network

struct OSDNotification: Decodable {
    let displayID: Int?
    let systemIconID: Int?
    let controlTarget: String?
    let value: Double?
    let maxValue: Double?
}

struct AppConfiguration: Codable {
    let monitor: MonitorConfiguration
    let lights: [LightConfiguration]
    let discovery: DiscoveryConfiguration

    init(
        monitor: MonitorConfiguration,
        lights: [LightConfiguration],
        discovery: DiscoveryConfiguration = .standard
    ) {
        self.monitor = monitor
        self.lights = lights
        self.discovery = discovery
    }

    private enum CodingKeys: String, CodingKey {
        case monitor
        case lights
        case discovery
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitor = try container.decode(MonitorConfiguration.self, forKey: .monitor)
        lights = try container.decode([LightConfiguration].self, forKey: .lights)
        discovery = try container.decodeIfPresent(
            DiscoveryConfiguration.self,
            forKey: .discovery
        ) ?? .standard
    }

    // Built-in defaults. Saved settings replace these values after the first save.
    static let current = AppConfiguration(
        monitor: MonitorConfiguration(displayID: 3),
        lights: [
            LightConfiguration(
                id: UUID(),
                name: "Light 1",
                ip: "192.168.1.2",
                isEnabled: false,
                port: 38899,
                mapping: BrightnessMapping(
                    monitorMin: 40,
                    monitorMax: 80,
                    lightMinPercent: 1,
                    lightMaxPercent: 100
                )
            ),
        ]
    )
}

struct MonitorConfiguration: Codable {
    let displayID: Int
}

struct DiscoveryConfiguration: Codable, Equatable {
    static let standard = DiscoveryConfiguration(
        responseWindowMilliseconds: 500,
        attemptCount: 3
    )
    static let responseWindowRange = 100...5_000
    static let attemptCountRange = 1...10

    let responseWindowMilliseconds: Int
    let attemptCount: Int

    init(responseWindowMilliseconds: Int, attemptCount: Int) {
        self.responseWindowMilliseconds = responseWindowMilliseconds
        self.attemptCount = attemptCount
    }

    private enum CodingKeys: String, CodingKey {
        case responseWindowMilliseconds
        case attemptCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedResponseWindow = try container.decodeIfPresent(
            Int.self,
            forKey: .responseWindowMilliseconds
        ) ?? Self.standard.responseWindowMilliseconds
        let decodedAttemptCount = try container.decodeIfPresent(
            Int.self,
            forKey: .attemptCount
        ) ?? Self.standard.attemptCount

        responseWindowMilliseconds = Self.responseWindowRange.contains(
            decodedResponseWindow
        ) ? decodedResponseWindow : Self.standard.responseWindowMilliseconds
        attemptCount = Self.attemptCountRange.contains(decodedAttemptCount)
            ? decodedAttemptCount
            : Self.standard.attemptCount
    }
}

struct LightConfiguration: Codable, Identifiable {
    var id: UUID
    var name: String
    var macAddress: String?
    var ip: String
    var isIPAddressVerified: Bool
    var isEnabled: Bool
    var port: UInt16
    var mapping: BrightnessMapping
    var deviceInfo: WiZDeviceInfo?

    init(
        id: UUID = UUID(),
        name: String = "",
        macAddress: String? = nil,
        ip: String,
        isIPAddressVerified: Bool = true,
        isEnabled: Bool = true,
        port: UInt16 = 38899,
        mapping: BrightnessMapping,
        deviceInfo: WiZDeviceInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.macAddress = macAddress
        self.ip = ip
        self.isIPAddressVerified = isIPAddressVerified
        self.isEnabled = isEnabled
        self.port = port
        self.mapping = mapping
        self.deviceInfo = deviceInfo
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case macAddress
        case ip
        case isIPAddressVerified
        case isEnabled
        case port
        case mapping
        case deviceInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        macAddress = try container.decodeIfPresent(String.self, forKey: .macAddress)
        ip = try container.decode(String.self, forKey: .ip)
        isIPAddressVerified = try container.decodeIfPresent(
            Bool.self,
            forKey: .isIPAddressVerified
        ) ?? true
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? 38899
        mapping = try container.decode(BrightnessMapping.self, forKey: .mapping)
        deviceInfo = try container.decodeIfPresent(WiZDeviceInfo.self, forKey: .deviceInfo)
    }

    var verifiedIPAddress: String? {
        isIPAddressVerified ? ip : nil
    }
}

struct WiZDeviceInfo: Codable {
    var moduleName: String?
    var firmwareVersion: String?
    var homeID: Int?
    var roomID: Int?
    var region: String?
}

struct BrightnessMapping: Codable {
    let monitorMin: Double
    let monitorMax: Double
    let lightMinPercent: Double
    let lightMaxPercent: Double

    init(
        monitorMin: Double,
        monitorMax: Double,
        lightMinPercent: Double,
        lightMaxPercent: Double
    ) {
        self.monitorMin = monitorMin
        self.monitorMax = monitorMax
        self.lightMinPercent = lightMinPercent
        self.lightMaxPercent = lightMaxPercent
    }

    private enum CodingKeys: String, CodingKey {
        case monitorMin
        case monitorMax
        case lightMinPercent
        case lightMaxPercent
        case lightMin
        case lightMax
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitorMin = try container.decode(Double.self, forKey: .monitorMin)
        monitorMax = try container.decode(Double.self, forKey: .monitorMax)

        if
            let savedLightMin = try container.decodeIfPresent(
                Double.self,
                forKey: .lightMinPercent
            ),
            let savedLightMax = try container.decodeIfPresent(
                Double.self,
                forKey: .lightMaxPercent
            )
        {
            lightMinPercent = savedLightMin
            lightMaxPercent = savedLightMax
        } else {
            // Earlier versions stored the WiZ protocol range (10–100),
            // which corresponds to the full user-visible range (1–100%).
            lightMinPercent = 1
            lightMaxPercent = 100
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(monitorMin, forKey: .monitorMin)
        try container.encode(monitorMax, forKey: .monitorMax)
        try container.encode(lightMinPercent, forKey: .lightMinPercent)
        try container.encode(lightMaxPercent, forKey: .lightMaxPercent)
    }

    func dimmingValue(for monitorBrightness: Double) -> Int {
        guard
            monitorBrightness.isFinite,
            monitorMin.isFinite,
            monitorMax.isFinite,
            lightMinPercent.isFinite,
            lightMaxPercent.isFinite,
            monitorMax > monitorMin,
            lightMaxPercent > lightMinPercent
        else {
            return Self.protocolDimmingValue(
                forVisiblePercentage: lightMinPercent
            )
        }

        let clampedMonitorBrightness = min(
            max(monitorBrightness, monitorMin),
            monitorMax
        )
        let normalizedMonitorBrightness =
            (clampedMonitorBrightness - monitorMin) /
            (monitorMax - monitorMin)
        let visibleLightBrightness = lightMinPercent +
            normalizedMonitorBrightness *
            (lightMaxPercent - lightMinPercent)

        return Self.protocolDimmingValue(
            forVisiblePercentage: visibleLightBrightness
        )
    }

    static func protocolDimmingValue(
        forVisiblePercentage visiblePercentage: Double
    ) -> Int {
        guard visiblePercentage.isFinite else { return 10 }

        let clampedPercentage = min(max(visiblePercentage, 1), 100)
        let normalizedPercentage = (clampedPercentage - 1) / 99
        return Int((10 + normalizedPercentage * 90).rounded())
    }
}

@MainActor
final class BrightnessController: ObservableObject {
    @Published private(set) var isPaused = false
    @Published private(set) var statusText = "Starting…"

    let configurationStore: ConfigurationStore

    private let notificationName = Notification.Name(
        "pro.betterdisplay.BetterDisplay.osd"
    )
    private var notificationObserver: NSObjectProtocol?
    private var udpConnections: [UUID: NWConnection] = [:]
    private var lastMonitorBrightness: Double?

    init() {
        self.configurationStore = ConfigurationStore()
        startListening()
        discoverLightsAtLaunch()
    }

    init(configurationStore: ConfigurationStore) {
        self.configurationStore = configurationStore
        startListening()
        discoverLightsAtLaunch()
    }

    private var configuration: AppConfiguration {
        configurationStore.configuration
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    func pause() {
        guard !isPaused else { return }

        isPaused = true
        cancelPendingUDPSends()
        statusText = "Sync paused"
        print("BetterBrightness paused")
    }

    func resume() {
        guard isPaused else { return }

        isPaused = false
        if let lastMonitorBrightness {
            sendBrightnessToEnabledLights(lastMonitorBrightness)
        } else {
            statusText = "Active · waiting for the next change"
        }
        print("BetterBrightness resumed")
    }

    private func startListening() {
        guard notificationObserver == nil else { return }

        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleNotification(notification)
            }
        }

        statusText = "Active · waiting for changes"
        print("Listening for BetterDisplay monitor \(configuration.monitor.displayID)")
    }

    private func discoverLightsAtLaunch() {
        print("Starting WiZ discovery at launch")

        let discoveryConfiguration = configuration.discovery

        WiZDiscoveryService.discover(
            configuration: discoveryConfiguration
        ) { attempt in
            print(
                "WiZ discovery attempt \(attempt) of " +
                    "\(discoveryConfiguration.attemptCount)"
            )
        } completion: { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let discoveredLights):
                do {
                    let summary = try self.configurationStore.applyDiscoveryResults(
                        discoveredLights
                    )
                    print(
                        "WiZ launch discovery found \(summary.foundLights) lights " +
                        "(\(summary.newLights) new, \(summary.updatedIPs) IP addresses updated)"
                    )
                } catch {
                    print("Could not save WiZ launch discovery results: \(error)")
                }

            case .failure(let error):
                print("WiZ launch discovery failed: \(error)")
            }
        }
    }

    private func handleNotification(_ notification: Notification) {
        guard
            let jsonString = notification.object as? String,
            let jsonData = jsonString.data(using: .utf8)
        else {
            print("BetterDisplay sent an unexpected notification payload")
            return
        }

        do {
            let event = try JSONDecoder().decode(OSDNotification.self, from: jsonData)

            // BetterDisplay uses systemIconID 1 for brightness changes.
            guard event.systemIconID == 1 else { return }
            guard event.displayID == configuration.monitor.displayID else { return }
            guard
                let value = event.value,
                let maxValue = event.maxValue,
                maxValue > 0
            else {
                print("Brightness event did not contain a valid value")
                return
            }

            let monitorBrightness = (value / maxValue) * 100
            lastMonitorBrightness = monitorBrightness

            guard !isPaused else {
                statusText = String(
                    format: "Sync paused · monitor %.0f%%",
                    monitorBrightness
                )
                return
            }

            sendBrightnessToEnabledLights(monitorBrightness)
        } catch {
            print("Could not decode BetterDisplay notification: \(error)")
        }
    }

    private func sendBrightnessToEnabledLights(_ monitorBrightness: Double) {
        let enabledLights = configuration.lights.filter {
            $0.isEnabled && $0.verifiedIPAddress != nil
        }
        let unavailableEnabledLightCount = configuration.lights.filter {
            $0.isEnabled && $0.verifiedIPAddress == nil
        }.count

        guard !isPaused else { return }

        if enabledLights.isEmpty {
            if unavailableEnabledLightCount > 0 {
                statusText = String(
                    format: "Monitor %.0f%% · waiting for %d lights",
                    monitorBrightness,
                    unavailableEnabledLightCount
                )
            } else {
                statusText = String(
                    format: "Monitor %.0f%% · no enabled lights",
                    monitorBrightness
                )
            }
            return
        }

        statusText = String(
            format: "Monitor %.0f%% · sending to %d lights",
            monitorBrightness,
            enabledLights.count
        )

        for light in enabledLights {
            let lightBrightness = light.mapping.dimmingValue(
                for: monitorBrightness
            )
            sendBrightness(lightBrightness, to: light)
        }
    }

    private func sendBrightness(_ brightness: Int, to light: LightConfiguration) {
        guard
            !isPaused,
            let ipAddress = light.verifiedIPAddress,
            let port = NWEndpoint.Port(rawValue: light.port)
        else {
            return
        }

        let payload = """
        {"id":1,"method":"setPilot","params":{"dimming":\(brightness)}}
        """
        guard let payloadData = payload.data(using: .utf8) else { return }

        let id = UUID()
        let connection = NWConnection(
            host: NWEndpoint.Host(ipAddress),
            port: port,
            using: .udp
        )
        udpConnections[id] = connection
        connection.start(queue: .main)
        connection.send(content: payloadData, completion: .contentProcessed {
            [weak self, weak connection] error in
            MainActor.assumeIsolated {
                guard let self else { return }

                self.udpConnections[id] = nil
                connection?.cancel()

                if let error {
                    print("Could not send UDP to \(ipAddress):\(light.port): \(error)")
                } else if !self.isPaused {
                    print("WiZ \(ipAddress):\(light.port) → \(brightness)%")
                }
            }
        })
    }

    private func cancelPendingUDPSends() {
        for connection in udpConnections.values {
            connection.cancel()
        }
        udpConnections.removeAll()
    }
}
