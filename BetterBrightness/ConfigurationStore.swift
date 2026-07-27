import Combine
import Foundation
import Network

enum ConfigurationError: LocalizedError {
    case invalidDisplayID
    case noLights
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
        case .invalidDisplayID:
            return "The monitor ID must be greater than zero."
        case .noLights:
            return "Add at least one WiZ light."
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
    private let storageKey = "betterBrightness.configuration"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if
            let data = defaults.data(forKey: storageKey),
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
        discovery: DiscoveryConfiguration? = nil
    ) throws {
        guard displayID > 0 else {
            throw ConfigurationError.invalidDisplayID
        }
        guard !lights.isEmpty else {
            throw ConfigurationError.noLights
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
        var usedAddresses = Set<String>()
        var usedMACAddresses = Set<String>()

        for light in lights {
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
                    isEnabled: light.isEnabled,
                    port: 38899,
                    mapping: BrightnessMapping(
                        monitorMin: light.mapping.monitorMin,
                        monitorMax: light.mapping.monitorMax,
                        lightMinPercent: light.mapping.lightMinPercent,
                        lightMaxPercent: light.mapping.lightMaxPercent
                    ),
                    deviceInfo: light.deviceInfo
                )
            )
        }

        let newConfiguration = AppConfiguration(
            monitor: MonitorConfiguration(displayID: displayID),
            lights: normalizedLights,
            discovery: discovery
        )
        try persist(newConfiguration)
    }

    func applyDiscoveryResults(
        _ discoveredLights: [DiscoveredWiZLight]
    ) throws -> DiscoveryMergeSummary {
        var lights = configuration.lights
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

        for discoveredLight in discoveredLights {
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

            lights.append(
                LightConfiguration(
                    name: discoveredLight.deviceInfo.moduleName ?? "WiZ Light",
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
            discovery: configuration.discovery
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
            discovery: configuration.discovery
        )
    }

    private func persist(_ newConfiguration: AppConfiguration) throws {
        let data = try JSONEncoder().encode(newConfiguration)
        defaults.set(data, forKey: storageKey)
        configuration = newConfiguration
    }
}
