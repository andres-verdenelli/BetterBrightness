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
    let groups: [LightGroup]
    let sidebarOrder: [UUID]
    let nextLightNumber: Int

    init(
        monitor: MonitorConfiguration,
        lights: [LightConfiguration],
        discovery: DiscoveryConfiguration = .standard,
        groups: [LightGroup] = [],
        nextLightNumber: Int? = nil,
        sidebarOrder: [UUID]? = nil
    ) {
        let grouped = Set(groups.flatMap(\.memberIDs))
        let entries: [(UUID, String)] = groups.map { ($0.id, $0.name) } + lights.filter { !$0.isHidden && !grouped.contains($0.id) }.map { ($0.id, Self.sidebarDisplayName($0)) }
        let valid = Set(entries.map { $0.0 })
        var seen = Set<UUID>()
        let preserved = (sidebarOrder ?? []).filter { valid.contains($0) && seen.insert($0).inserted }
        let sortedEntries = entries.sorted {
            let order = $0.1.localizedStandardCompare($1.1)
            return order == .orderedSame ? $0.0.uuidString < $1.0.uuidString : order == .orderedAscending
        }
        self.sidebarOrder = preserved + sortedEntries.map { $0.0 }.filter { seen.insert($0).inserted }
        self.monitor = monitor
        self.lights = lights
        self.discovery = discovery
        self.groups = groups
        self.nextLightNumber = max(nextLightNumber ?? 1, Self.inferredNextLightNumber(lights))
    }

    private enum CodingKeys: String, CodingKey {
        case monitor
        case lights
        case discovery
        case groups
        case sidebarOrder
        case nextLightNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lights = try container.decode([LightConfiguration].self, forKey: .lights)
        var groups = try container.decodeIfPresent([LightGroup].self, forKey: .groups) ?? []
        let order = try container.decodeIfPresent([UUID].self, forKey: .sidebarOrder)
        if order == nil {
            for index in groups.indices {
                groups[index].memberIDs.sort { a, b in
                    let first = lights.first { $0.id == a }.map(Self.sidebarDisplayName) ?? "Unnamed Light"
                    let second = lights.first { $0.id == b }.map(Self.sidebarDisplayName) ?? "Unnamed Light"
                    let comparison = first.localizedStandardCompare(second)
                    return comparison == .orderedSame ? a.uuidString < b.uuidString : comparison == .orderedAscending
                }
            }
        }
        self.init(monitor: try container.decode(MonitorConfiguration.self, forKey: .monitor),
                  lights: lights,
                  discovery: try container.decodeIfPresent(DiscoveryConfiguration.self, forKey: .discovery) ?? .standard,
                  groups: groups,
                  nextLightNumber: try container.decodeIfPresent(Int.self, forKey: .nextLightNumber),
                  sidebarOrder: order)
    }

    private static func sidebarDisplayName(_ light: LightConfiguration) -> String {
        let name = light.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unnamed Light" : name
    }

    private static func inferredNextLightNumber(_ lights: [LightConfiguration]) -> Int {
        lights.reduce(1) { next, light in
            let name = light.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.hasPrefix("Light "),
                  let number = Int(name.dropFirst(6)), number > 0,
                  name == "Light \(number)" else { return next }
            return max(next, number == Int.max ? Int.max : number + 1)
        }
    }

    // Built-in defaults. Saved settings replace these values after the first save.
    static let current = AppConfiguration(
        monitor: MonitorConfiguration(displayID: 3),
        lights: []
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
    var isHidden: Bool
    var port: UInt16
    var mapping: BrightnessMapping
    var deviceInfo: WiZDeviceInfo?
    var brightnessOffset: Int
    var showInMenu: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        macAddress: String? = nil,
        ip: String,
        isIPAddressVerified: Bool = true,
        isEnabled: Bool = true,
        isHidden: Bool = false,
        port: UInt16 = 38899,
        mapping: BrightnessMapping,
        deviceInfo: WiZDeviceInfo? = nil,
        brightnessOffset: Int = 0,
        showInMenu: Bool = false
    ) {
        self.id = id
        self.name = name
        self.macAddress = macAddress
        self.ip = ip
        self.isIPAddressVerified = isIPAddressVerified
        self.isEnabled = isEnabled
        self.isHidden = isHidden
        self.port = port
        self.mapping = mapping
        self.deviceInfo = deviceInfo
        self.brightnessOffset = min(30, max(-30, brightnessOffset))
        self.showInMenu = showInMenu
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case macAddress
        case ip
        case isIPAddressVerified
        case isEnabled
        case isHidden
        case port
        case mapping
        case deviceInfo
        case brightnessOffset, showInMenu
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
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? 38899
        mapping = try container.decode(BrightnessMapping.self, forKey: .mapping)
        deviceInfo = try container.decodeIfPresent(WiZDeviceInfo.self, forKey: .deviceInfo)
        brightnessOffset = min(30, max(-30, try container.decodeIfPresent(Int.self, forKey: .brightnessOffset) ?? 0))
        showInMenu = try container.decodeIfPresent(Bool.self, forKey: .showInMenu) ?? false
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

struct BrightnessMapping: Codable, Equatable {
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

    func dimmingValue(for monitorBrightness: Double, offset: Int = 0) -> Int {
        Self.protocolDimmingValue(forVisiblePercentage: visiblePercentage(for: monitorBrightness) + Double(offset))
    }

    func visiblePercentage(for monitorBrightness: Double) -> Double {
        guard
            monitorBrightness.isFinite,
            monitorMin.isFinite,
            monitorMax.isFinite,
            lightMinPercent.isFinite,
            lightMaxPercent.isFinite,
            monitorMax > monitorMin,
            lightMaxPercent > lightMinPercent
        else {
            return lightMinPercent
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

        return visibleLightBrightness
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
    let discoveryController: DiscoveryController

    private let notificationName = Notification.Name(
        "pro.betterdisplay.BetterDisplay.osd"
    )
    private var notificationObserver: NSObjectProtocol?
    private var udpConnections: [UUID: NWConnection] = [:]
    @Published private(set) var lastMonitorBrightness: Double?
    @Published private(set) var offsetSaveError: String?
    private var snapshot: AppConfiguration
    private var configurationSubscription: AnyCancellable?
    private let now: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping () -> Void) -> (() -> Void)
    private var savingOffset = false
    private final class Adjustment {
        var offset: Int
        var lastSend: TimeInterval?
        var sent: [UUID: Int] = [:]
        var cancel: (() -> Void)?
        init(offset: Int) { self.offset = offset }
    }
    private var adjustments: [UUID: Adjustment] = [:]
    private let permitsNetwork: Bool
    private let sendOverride: ((Int, LightConfiguration) -> Void)?

    convenience init() {
        self.init(configurationStore: ConfigurationStore())
    }

    init(configurationStore: ConfigurationStore, startsServices: Bool = true,
         send: ((Int, LightConfiguration) -> Void)? = nil,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> (() -> Void) = { delay, action in
             let timer = Timer(timeInterval: delay, repeats: false) { _ in action() }
             RunLoop.main.add(timer, forMode: .common)
             return { timer.invalidate() }
         }) {
        snapshot = configurationStore.configuration
        self.now = now
        self.schedule = schedule
        permitsNetwork = startsServices
        sendOverride = send
        self.configurationStore = configurationStore
        if startsServices {
            self.discoveryController = DiscoveryController(configurationStore: configurationStore)
        } else {
            self.discoveryController = DiscoveryController(configurationStore: configurationStore) { _, _, completion in
                completion(.success([]))
            }
        }
        configurationSubscription = configurationStore.$configuration.dropFirst().sink { [weak self] next in
            self?.configurationChanged(next)
        }
        if startsServices {
            startListening()
            discoveryController.discoverLights()
        } else {
            statusText = "Simulated preview · no device control"
        }
    }

    private var configuration: AppConfiguration {
        snapshot
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    func pause() {
        guard !isPaused else { return }

        isPaused = true
        cancelAdjustments()
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

    func sendBrightnessToEnabledLights(_ monitorBrightness: Double) {
        guard monitorBrightness.isFinite else { return }
        lastMonitorBrightness = monitorBrightness
        let effectiveLights = configuration.effectiveLights
        let enabledLights = effectiveLights.filter {
            !$0.isHidden && $0.isEnabled && $0.verifiedIPAddress != nil
        }
        let unavailableEnabledLightCount = effectiveLights.filter {
            !$0.isHidden && $0.isEnabled && $0.verifiedIPAddress == nil
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

        for id in configuration.sidebarOrder {
            requestSend(to: id)
        }
    }

    var menuDestinations: [(id: UUID, name: String)] {
        configuration.sidebarOrder.compactMap { id in
            if let g = configuration.groups.first(where: { $0.id == id && $0.showInMenu && $0.isEnabled }) {
                return (id, g.name)
            }
            if let l = configuration.lights.first(where: { $0.id == id && !$0.isHidden && $0.showInMenu && $0.isEnabled }),
               configuration.group(containing: id) == nil {
                return (id, l.name.isEmpty ? "Unnamed Light" : l.name)
            }
            return nil
        }
    }

    func offset(for id: UUID) -> Int {
        adjustments[id]?.offset ?? configuration.groups.first(where: { $0.id == id })?.brightnessOffset
            ?? configuration.lights.first(where: { $0.id == id })?.brightnessOffset ?? 0
    }

    func disabledReason(for id: UUID) -> String? {
        guard menuDestinations.contains(where: { $0.id == id }) else { return "Destination unavailable" }
        if isPaused { return "Sync paused" }
        let lights = destinationLights(id)
        if lights.isEmpty { return "Destination unavailable" }
        if !lights.contains(where: { $0.isEnabled }) { return "Sync is off" }
        if lastMonitorBrightness == nil { return "Waiting for monitor brightness" }
        if !lights.contains(where: { $0.isEnabled && $0.verifiedIPAddress != nil }) { return "Waiting for rediscovery" }
        return nil
    }

    private func destinationLights(_ id: UUID) -> [LightConfiguration] {
        let members = configuration.groups.first(where: { $0.id == id })?.memberIDs ?? [id]
        return configuration.effectiveLights.filter { members.contains($0.id) && !$0.isHidden }
    }

    func changeOffset(_ value: Int, for id: UUID) {
        guard disabledReason(for: id) == nil, menuDestinations.contains(where: { $0.id == id }) else { return }
        if adjustments[id] == nil { adjustments[id] = Adjustment(offset: offset(for: id)) }
        adjustments[id]?.offset = min(30, max(-30, value))
        objectWillChange.send()
        requestSend(to: id)
    }

    func finishOffsetAdjustment(_ id: UUID) {
        guard let adjustment = adjustments[id] else { return }
        adjustment.cancel?()
        adjustment.cancel = nil
        transmit(to: id, adjustment: adjustment)
        savingOffset = true
        do {
            try configurationStore.setBrightnessOffset(adjustment.offset, for: id)
            offsetSaveError = nil
            adjustments[id] = nil
        } catch {
            adjustments[id] = nil
            offsetSaveError = "Could not save brightness adjustment: \(error.localizedDescription)"
            requestSend(to: id) // Restore the persisted value, including on the transport.
        }
        savingOffset = false
        objectWillChange.send()
    }

    func clearOffsetSaveError() { offsetSaveError = nil }

    private func requestSend(to id: UUID) {
        guard !isPaused, lastMonitorBrightness != nil else { return }
        guard let adjustment = adjustments[id] else { transmit(to: id, adjustment: nil); return }
        let remaining = 0.3 - (now() - (adjustment.lastSend ?? (now() - 0.3)))
        if adjustment.lastSend == nil || remaining <= 0 {
            adjustment.cancel?()
            adjustment.cancel = nil
            transmit(to: id, adjustment: adjustment)
        } else if adjustment.cancel == nil {
            adjustment.cancel = schedule(remaining) { [weak self, weak adjustment] in
                guard let self, let adjustment, self.adjustments[id] === adjustment else { return }
                adjustment.cancel = nil
                self.transmit(to: id, adjustment: adjustment)
            }
        }
    }

    private func transmit(to id: UUID, adjustment: Adjustment?) {
        guard !isPaused, let monitor = lastMonitorBrightness else { return }
        var didSend = false
        for light in destinationLights(id) where light.isEnabled && light.verifiedIPAddress != nil {
            let brightness = light.mapping.dimmingValue(for: monitor, offset: offset(for: id))
            if let adjustment, adjustment.sent[light.id] == brightness { continue }
            sendBrightness(brightness, to: light)
            adjustment?.sent[light.id] = brightness
            didSend = true
        }
        if didSend { adjustment?.lastSend = now() }
    }

    private func cancelAdjustments() {
        // Persist the latest user value when Pause interrupts a gesture; no final send.
        let interrupted = adjustments
        adjustments.removeAll()
        for (id, adjustment) in interrupted {
            adjustment.cancel?()
            savingOffset = true
            do { try configurationStore.setBrightnessOffset(adjustment.offset, for: id) }
            catch { offsetSaveError = "Could not save brightness adjustment: \(error.localizedDescription)" }
            savingOffset = false
        }
    }

    private func configurationChanged(_ next: AppConfiguration) {
        let previous = snapshot
        let monitorChanged = previous.monitor.displayID != next.monitor.displayID
        snapshot = next
        guard !savingOffset else { return }
        for (id, adjustment) in adjustments {
            let oldMembers = previous.groups.first(where: { $0.id == id })?.memberIDs ?? [id]
            let newMembers = next.groups.first(where: { $0.id == id })?.memberIDs ?? [id]
            let oldLights = previous.effectiveLights.filter { oldMembers.contains($0.id) }
            let newLights = next.effectiveLights.filter { newMembers.contains($0.id) }
            let routesChanged = oldMembers != newMembers || oldLights.count != newLights.count || oldLights.contains { old in
                guard let new = newLights.first(where: { $0.id == old.id }) else { return true }
                return old.ip != new.ip || old.isIPAddressVerified != new.isIPAddressVerified ||
                    old.isHidden != new.isHidden || old.isEnabled != new.isEnabled || old.mapping != new.mapping ||
                    old.brightnessOffset != new.brightnessOffset
            }
            if monitorChanged || routesChanged || disabledReason(for: id) != nil {
                adjustment.cancel?()
                adjustments[id] = nil
            }
        }
        cancelPendingUDPSends()
        if monitorChanged { lastMonitorBrightness = nil }
        objectWillChange.send()
        if let monitor = lastMonitorBrightness { sendBrightnessToEnabledLights(monitor) }
    }

    private func sendBrightness(_ brightness: Int, to light: LightConfiguration) {
        guard
            !isPaused,
            !light.isHidden,
            let ipAddress = light.verifiedIPAddress,
            let port = NWEndpoint.Port(rawValue: light.port)
        else {
            return
        }

        if let sendOverride { sendOverride(brightness, light); return }
        guard permitsNetwork else { return }

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

/// A group owns the effective Sync and mapping. Members retain their UUID and device identity.
struct LightGroup: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var memberIDs: [UUID]
    var isEnabled: Bool
    var mapping: BrightnessMapping
    var brightnessOffset: Int = 0
    var showInMenu: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, memberIDs, isEnabled, mapping, brightnessOffset, showInMenu
    }

    init(id: UUID = UUID(), name: String, memberIDs: [UUID], isEnabled: Bool,
         mapping: BrightnessMapping, brightnessOffset: Int = 0, showInMenu: Bool = false) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.isEnabled = isEnabled
        self.mapping = mapping
        self.brightnessOffset = min(30, max(-30, brightnessOffset))
        self.showInMenu = showInMenu
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                  memberIDs: try c.decode([UUID].self, forKey: .memberIDs),
                  isEnabled: try c.decode(Bool.self, forKey: .isEnabled),
                  mapping: try c.decode(BrightnessMapping.self, forKey: .mapping),
                  brightnessOffset: try c.decodeIfPresent(Int.self, forKey: .brightnessOffset) ?? 0,
                  showInMenu: try c.decodeIfPresent(Bool.self, forKey: .showInMenu) ?? false)
    }
}

extension AppConfiguration {
    func group(containing lightID: UUID) -> LightGroup? {
        groups.first { $0.memberIDs.contains(lightID) }
    }

    var effectiveLights: [LightConfiguration] {
        lights.map { light in
            var effective = light
            if let group = group(containing: light.id) {
                effective.isEnabled = group.isEnabled
                effective.mapping = group.mapping
                effective.brightnessOffset = group.brightnessOffset
                effective.showInMenu = false
            }
            if light.isHidden { effective.isEnabled = false }
            return effective
        }
    }
}

/// Root-level insertion treats an expanded folder and its descendants as one block.
enum SidebarOrder {
    static func rootInsertion(roots: [UUID], children: [UUID: [UUID]], hovered: UUID, afterHeader: Bool) -> Int? {
        let root = children.first(where: { $0.value.contains(hovered) })?.key ?? hovered
        guard let index = roots.firstIndex(of: root) else { return nil }
        return index + (afterHeader ? 1 : 0)
    }
}
