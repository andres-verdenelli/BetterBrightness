import Combine
import Foundation
import Network

enum ConfigurationError: LocalizedError {
    case invalidGroup(String)
    case storageFailure
    case invalidDisplayID
    case lightNumberExhausted
    case invalidIPAddress(String)
    case invalidMACAddress(String)
    case duplicateIPAddress(String)
    case duplicateMACAddress(String)
    case conflictingDiscoveryIPAddress(String)
    case invalidMonitorRange(String)
    case invalidLightRange(String)
    case invalidDiscoveryResponseWindow
    case invalidDiscoveryAttemptCount

    var errorDescription: String? {
        switch self {
        case .invalidGroup(let message):
            return message
        case .storageFailure:
            return "The configuration could not be saved. No changes were applied."
        case .invalidDisplayID:
            return "The monitor ID must be greater than zero."
        case .lightNumberExhausted:
            return "No more default light numbers are available."
        case .invalidIPAddress(let ip):
            return "\(ip.isEmpty ? "One light" : ip) is not a valid IPv4 address."
        case .invalidMACAddress(let macAddress):
            return "\(macAddress) is not a valid MAC address."
        case .duplicateIPAddress(let ip):
            return "The IP address \(ip) was entered more than once."
        case .duplicateMACAddress(let macAddress):
            return "The MAC address \(WiZMACAddress.display(macAddress)) was entered more than once."
        case .conflictingDiscoveryIPAddress(let ip):
            return "More than one responding WiZ light reported the IP address \(ip). No discovery changes were saved."
        case .invalidMonitorRange(let ip):
            return "The monitor range for \(ip) must be between 0 and 100, with the minimum below the maximum."
        case .invalidLightRange(let name):
            return "The light range for \(name) must be between 1 and 100, with the minimum below the maximum."
        case .invalidDiscoveryResponseWindow:
            return "The discovery response window must be between 100 and 5,000 milliseconds."
        case .invalidDiscoveryAttemptCount:
            return "Discovery attempts must be between 1 and 10."
        }
    }
}

@MainActor
final class ConfigurationStore: ObservableObject {
    @Published private(set) var configuration: AppConfiguration

    private let defaults: UserDefaults
    private let fileURL: URL?
    private let writeData: ((Data) throws -> Void)?
    private let storageKey = "betterBrightness.configuration"

    convenience init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let file = root.appendingPathComponent(Bundle.main.bundleIdentifier ?? "BetterBrightness", isDirectory: true)
            .appendingPathComponent("Configuration.json")
        self.init(defaults: .standard, fileURL: file)
    }

    init(defaults: UserDefaults, fileURL: URL? = nil, writeData: ((Data) throws -> Void)? = nil) {
        self.defaults = defaults
        self.writeData = writeData
        self.fileURL = fileURL

        if
            let data = fileURL.flatMap({ try? Data(contentsOf: $0) }) ?? defaults.data(forKey: storageKey),
            let savedConfiguration = try? JSONDecoder().decode(
                AppConfiguration.self,
                from: data
            )
        {
            configuration = Self.invalidatingAmbiguousAddresses(
                in: savedConfiguration
            )
        } else {
            configuration = .current
        }
    }

    func save(
        displayID: Int,
        lights: [LightConfiguration],
        discovery: DiscoveryConfiguration? = nil,
        groups: [LightGroup]? = nil
    ) throws {
        guard displayID > 0 else {
            throw ConfigurationError.invalidDisplayID
        }

        let discovery = discovery ?? configuration.discovery
        guard DiscoveryConfiguration.responseWindowRange.contains(
            discovery.responseWindowMilliseconds
        ) else {
            throw ConfigurationError.invalidDiscoveryResponseWindow
        }
        guard DiscoveryConfiguration.attemptCountRange.contains(
            discovery.attemptCount
        ) else {
            throw ConfigurationError.invalidDiscoveryAttemptCount
        }

        var normalizedLights: [LightConfiguration] = []
        var usedIDs = Set<UUID>()
        var usedAddresses = Set<String>()
        var usedMACAddresses = Set<String>()

        for light in lights {
            guard usedIDs.insert(light.id).inserted else {
                throw ConfigurationError.invalidGroup("Each light must have a unique identity.")
            }
            let ip = light.ip.trimmingCharacters(in: .whitespacesAndNewlines)

            guard IPv4Address(ip) != nil else {
                throw ConfigurationError.invalidIPAddress(ip)
            }
            if light.isIPAddressVerified {
                guard usedAddresses.insert(ip).inserted else {
                    throw ConfigurationError.duplicateIPAddress(ip)
                }
            }

            let normalizedMACAddress: String?
            if let macAddress = light.macAddress {
                guard let normalized = WiZMACAddress.normalized(macAddress) else {
                    throw ConfigurationError.invalidMACAddress(macAddress)
                }
                guard usedMACAddresses.insert(normalized).inserted else {
                    throw ConfigurationError.duplicateMACAddress(normalized)
                }
                normalizedMACAddress = normalized
            } else {
                normalizedMACAddress = nil
            }

            guard
                (0...100).contains(light.mapping.monitorMin),
                (0...100).contains(light.mapping.monitorMax),
                light.mapping.monitorMin.isFinite,
                light.mapping.monitorMax.isFinite,
                light.mapping.monitorMin < light.mapping.monitorMax
            else {
                throw ConfigurationError.invalidMonitorRange(ip)
            }

            guard
                (1...100).contains(light.mapping.lightMinPercent),
                (1...100).contains(light.mapping.lightMaxPercent),
                light.mapping.lightMinPercent.isFinite,
                light.mapping.lightMaxPercent.isFinite,
                light.mapping.lightMinPercent < light.mapping.lightMaxPercent
            else {
                let lightName = light.name.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                throw ConfigurationError.invalidLightRange(
                    lightName.isEmpty ? ip : lightName
                )
            }

            normalizedLights.append(
                LightConfiguration(
                    id: light.id,
                    name: light.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    macAddress: normalizedMACAddress,
                    ip: ip,
                    isIPAddressVerified: light.isIPAddressVerified,
                    isEnabled: light.isHidden ? false : light.isEnabled,
                    isHidden: light.isHidden,
                    port: 38899,
                    mapping: BrightnessMapping(
                        monitorMin: light.mapping.monitorMin,
                        monitorMax: light.mapping.monitorMax,
                        lightMinPercent: light.mapping.lightMinPercent,
                        lightMaxPercent: light.mapping.lightMaxPercent
                    ),
                    deviceInfo: light.deviceInfo,
                    brightnessOffset: light.isHidden ? 0 : min(30, max(-30, light.brightnessOffset)),
                    showInMenu: !light.isHidden && light.showInMenu
                )
            )
        }

        var groups = try validatedGroups(groups ?? configuration.groups, lights: normalizedLights)
        for g in groups.indices {
            groups[g].brightnessOffset = min(30, max(-30, groups[g].brightnessOffset))
            if !groups[g].showInMenu && configuration.groups.first(where: { $0.id == groups[g].id })?.showInMenu == true {
                groups[g].brightnessOffset = 0
            }
        }
        for i in normalizedLights.indices {
            if groups.contains(where: { $0.memberIDs.contains(normalizedLights[i].id) }) {
                normalizedLights[i].showInMenu = false
                normalizedLights[i].brightnessOffset = 0
            } else if !normalizedLights[i].showInMenu && configuration.lights.first(where: { $0.id == normalizedLights[i].id })?.showInMenu == true {
                normalizedLights[i].brightnessOffset = 0
            }
        }
        let newConfiguration = AppConfiguration(
            monitor: MonitorConfiguration(displayID: displayID),
            lights: normalizedLights,
            discovery: discovery,
            groups: groups,
            nextLightNumber: configuration.nextLightNumber,
            sidebarOrder: configuration.sidebarOrder
        )
        try persist(newConfiguration)
    }

    func setBrightnessOffset(_ offset: Int, for id: UUID) throws {
        var lights = configuration.lights
        var groups = configuration.groups
        if let g = groups.firstIndex(where: { $0.id == id && $0.showInMenu }) {
            groups[g].brightnessOffset = offset
        } else if let i = lights.firstIndex(where: { $0.id == id && !$0.isHidden && $0.showInMenu }),
                  configuration.group(containing: id) == nil {
            lights[i].brightnessOffset = offset
        } else {
            throw ConfigurationError.invalidGroup("This menu destination is no longer available.")
        }
        try save(displayID: configuration.monitor.displayID, lights: lights, groups: groups)
    }

    func applyDiscoveryResults(
        _ discoveredLights: [DiscoveredWiZLight]
    ) throws -> DiscoveryMergeSummary {
        var lights = configuration.lights
        var nextLightNumber = configuration.nextLightNumber
        var newLightCount = 0
        var updatedIPCount = 0
        var identifiedExistingLightCount = 0
        var respondingMACByIPAddress: [String: String] = [:]

        for discoveredLight in discoveredLights {
            if
                let respondingMAC = respondingMACByIPAddress[
                    discoveredLight.ipAddress
                ],
                respondingMAC != discoveredLight.macAddress
            {
                throw ConfigurationError.conflictingDiscoveryIPAddress(
                    discoveredLight.ipAddress
                )
            }

            respondingMACByIPAddress[discoveredLight.ipAddress] =
                discoveredLight.macAddress
        }

        for discoveredLight in discoveredLights.sorted(by: { $0.macAddress < $1.macAddress }) {
            if let index = lights.firstIndex(where: { light in
                light.macAddress.flatMap(WiZMACAddress.normalized) ==
                    discoveredLight.macAddress
            }) {
                if lights[index].ip != discoveredLight.ipAddress {
                    lights[index].ip = discoveredLight.ipAddress
                    updatedIPCount += 1
                }
                lights[index].macAddress = discoveredLight.macAddress
                lights[index].isIPAddressVerified = true
                lights[index].deviceInfo = discoveredLight.deviceInfo
                continue
            }

            if let index = lights.firstIndex(where: {
                $0.macAddress == nil && $0.ip == discoveredLight.ipAddress
            }) {
                lights[index].macAddress = discoveredLight.macAddress
                lights[index].isIPAddressVerified = true
                lights[index].deviceInfo = discoveredLight.deviceInfo
                identifiedExistingLightCount += 1
                continue
            }

            guard nextLightNumber < Int.max else { throw ConfigurationError.lightNumberExhausted }
            let name = "Light \(nextLightNumber)"
            nextLightNumber += 1
            lights.append(
                LightConfiguration(
                    name: name,
                    macAddress: discoveredLight.macAddress,
                    ip: discoveredLight.ipAddress,
                    isIPAddressVerified: true,
                    isEnabled: false,
                    mapping: BrightnessMapping(
                        monitorMin: 40,
                        monitorMax: 80,
                        lightMinPercent: 1,
                        lightMaxPercent: 100
                    ),
                    deviceInfo: discoveredLight.deviceInfo
                )
            )
            newLightCount += 1
        }

        var invalidatedLightIDs = Set<UUID>()

        for discoveredLight in discoveredLights {
            guard let respondingIndex = lights.firstIndex(where: { light in
                light.macAddress.flatMap(WiZMACAddress.normalized) ==
                    discoveredLight.macAddress
            }) else {
                continue
            }

            let respondingLightID = lights[respondingIndex].id

            for index in lights.indices where
                lights[index].id != respondingLightID &&
                lights[index].ip == discoveredLight.ipAddress &&
                lights[index].isIPAddressVerified
            {
                lights[index].isIPAddressVerified = false
                invalidatedLightIDs.insert(lights[index].id)
            }
        }

        let newConfiguration = AppConfiguration(
            monitor: configuration.monitor,
            lights: lights,
            discovery: configuration.discovery,
            groups: configuration.groups,
            nextLightNumber: nextLightNumber,
            sidebarOrder: configuration.sidebarOrder
        )
        try persist(newConfiguration)

        return DiscoveryMergeSummary(
            foundLights: discoveredLights.count,
            newLights: newLightCount,
            updatedIPs: updatedIPCount,
            identifiedExistingLights: identifiedExistingLightCount,
            invalidatedIPs: invalidatedLightIDs.count
        )
    }

    private func validatedGroups(_ groups: [LightGroup], lights: [LightConfiguration]) throws -> [LightGroup] {
        var names = Set<String>()
        var groupIDs = Set<UUID>()
        var members = Set<UUID>()
        return try groups.map { group in
            var result = group
            result.name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.name.isEmpty, names.insert(result.name.lowercased()).inserted else {
                throw ConfigurationError.invalidGroup("Use a nonempty, unique group name.")
            }
            guard groupIDs.insert(group.id).inserted, !group.memberIDs.isEmpty else {
                throw ConfigurationError.invalidGroup("Groups must have a unique identity and at least one light.")
            }
            for id in group.memberIDs {
                guard lights.contains(where: { $0.id == id && !$0.isHidden }), members.insert(id).inserted else {
                    throw ConfigurationError.invalidGroup("Each visible light can belong to only one group.")
                }
            }
            let m = group.mapping
            guard m.monitorMin.isFinite, m.monitorMax.isFinite,
                  (0...100).contains(m.monitorMin), (0...100).contains(m.monitorMax), m.monitorMin < m.monitorMax,
                  m.lightMinPercent.isFinite, m.lightMaxPercent.isFinite,
                  (1...100).contains(m.lightMinPercent), (1...100).contains(m.lightMaxPercent), m.lightMinPercent < m.lightMaxPercent else {
                throw ConfigurationError.invalidGroup("The group brightness ranges are invalid.")
            }
            return result
        }
    }

    @discardableResult
    func createGroup(name: String, memberIDs: Set<UUID>, sourceID: UUID) throws -> UUID {
        guard memberIDs.count >= 2, memberIDs.contains(sourceID),
              let source = configuration.lights.first(where: { $0.id == sourceID }),
              memberIDs.allSatisfy({ id in
                  configuration.lights.contains { $0.id == id && !$0.isHidden } && configuration.group(containing: id) == nil
              }) else {
            throw ConfigurationError.invalidGroup("Select at least two independent, visible lights.")
        }
        let group = LightGroup(name: name, memberIDs: configuration.lights.filter { memberIDs.contains($0.id) }.map(\.id),
                               isEnabled: source.isEnabled, mapping: source.mapping)
        try save(displayID: configuration.monitor.displayID, lights: configuration.lights,
                 groups: configuration.groups + [group])
        return group.id
    }

    func updateGroup(_ group: LightGroup) throws {
        guard let index = configuration.groups.firstIndex(where: { $0.id == group.id }),
              Set(group.memberIDs) == Set(configuration.groups[index].memberIDs) else {
            throw ConfigurationError.invalidGroup("The group changed. Select it again before editing.")
        }
        var groups = configuration.groups
        groups[index] = group
        try save(displayID: configuration.monitor.displayID, lights: configuration.lights, groups: groups)
    }

    /// One save commits both membership and copied outgoing settings.
    func moveLights(_ ids: Set<UUID>, to destinationID: UUID?) throws {
        guard !ids.isEmpty, ids.allSatisfy({ id in configuration.lights.contains { $0.id == id && !$0.isHidden } }),
              destinationID == nil || configuration.groups.contains(where: { $0.id == destinationID }) else {
            throw ConfigurationError.invalidGroup("Select visible lights and an existing destination group.")
        }
        var lights = configuration.lights
        var groups = configuration.groups
        for index in lights.indices where ids.contains(lights[index].id) {
            let id = lights[index].id
            if configuration.group(containing: id)?.id == destinationID { continue }
            if let previous = configuration.group(containing: id) {
                lights[index].brightnessOffset = previous.brightnessOffset
                lights[index].showInMenu = previous.showInMenu
                lights[index].mapping = previous.mapping
                lights[index].isEnabled = true
            }
            for g in groups.indices { groups[g].memberIDs.removeAll { $0 == id } }
            if let destinationID, let g = groups.firstIndex(where: { $0.id == destinationID }) {
                groups[g].memberIDs.append(id)
            }
        }
        groups.removeAll { $0.memberIDs.isEmpty }
        try save(displayID: configuration.monitor.displayID, lights: lights, groups: groups)
    }

    /// Index is a slot in the original sibling list, before removing dragged IDs.
    func reorderSidebar(_ ids: Set<UUID>, parent: UUID?, index: Int) throws {
        var groups = configuration.groups
        let siblings: [UUID]
        if let parent {
            guard let group = groups.first(where: { $0.id == parent }) else {
                throw ConfigurationError.invalidGroup("The group no longer exists.")
            }
            siblings = group.memberIDs
        } else { siblings = configuration.sidebarOrder }
        guard !ids.isEmpty, ids.isSubset(of: Set(siblings)), (0...siblings.count).contains(index) else {
            throw ConfigurationError.invalidGroup("Reorder items within the same group or sidebar level.")
        }
        let moving = siblings.filter { ids.contains($0) }
        var reordered = siblings.filter { !ids.contains($0) }
        let insertion = index - siblings.prefix(index).filter { ids.contains($0) }.count
        reordered.insert(contentsOf: moving, at: insertion)
        guard reordered != siblings else { return }
        if let parent, let g = groups.firstIndex(where: { $0.id == parent }) { groups[g].memberIDs = reordered }
        let next = AppConfiguration(monitor: configuration.monitor, lights: configuration.lights,
                                    discovery: configuration.discovery, groups: groups,
                                    nextLightNumber: configuration.nextLightNumber,
                                    sidebarOrder: parent == nil ? reordered : configuration.sidebarOrder)
        try persist(next)
    }

    func ungroup(_ id: UUID) throws {
        guard let group = configuration.groups.first(where: { $0.id == id }) else { return }
        try moveLights(Set(group.memberIDs), to: nil)
    }

    func setLightHidden(_ id: UUID, hidden: Bool) throws {
        guard let index = configuration.lights.firstIndex(where: { $0.id == id }) else { return }
        var lights = configuration.lights
        var groups = configuration.groups
        if let group = configuration.group(containing: id) { lights[index].mapping = group.mapping }
        lights[index].brightnessOffset = 0
        lights[index].showInMenu = false
        lights[index].isHidden = hidden
        lights[index].isEnabled = false
        for g in groups.indices { groups[g].memberIDs.removeAll { $0 == id } }
        groups.removeAll { $0.memberIDs.isEmpty }
        try save(displayID: configuration.monitor.displayID, lights: lights, groups: groups)
    }

    func removeLight(_ id: UUID) throws {
        let lights = configuration.lights.filter { $0.id != id }
        var groups = configuration.groups
        for g in groups.indices { groups[g].memberIDs.removeAll { $0 == id } }
        groups.removeAll { $0.memberIDs.isEmpty }
        try save(displayID: configuration.monitor.displayID, lights: lights, groups: groups)
    }

    private static func invalidatingAmbiguousAddresses(
        in configuration: AppConfiguration
    ) -> AppConfiguration {
        var lights = configuration.lights
        var indicesByIPAddress: [String: [Int]] = [:]

        for index in lights.indices where lights[index].isIPAddressVerified {
            indicesByIPAddress[lights[index].ip, default: []].append(index)
        }

        for indices in indicesByIPAddress.values where indices.count > 1 {
            for index in indices {
                lights[index].isIPAddressVerified = false
            }
        }

        return AppConfiguration(
            monitor: configuration.monitor,
            lights: lights,
            discovery: configuration.discovery,
            groups: configuration.groups,
            nextLightNumber: configuration.nextLightNumber,
            sidebarOrder: configuration.sidebarOrder
        )
    }

    private func persist(_ newConfiguration: AppConfiguration) throws {
        let data = try JSONEncoder().encode(newConfiguration)
        if let writeData {
            try writeData(data)
        } else if let fileURL {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } else {
            defaults.set(data, forKey: storageKey)
            guard defaults.data(forKey: storageKey) == data else {
                throw ConfigurationError.storageFailure
            }
        }
        configuration = newConfiguration
    }
}
