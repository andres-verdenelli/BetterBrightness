import Foundation

struct LightDraft: Identifiable {
    let id: UUID
    var name: String
    var macAddress: String?
    var ip: String
    var isIPAddressVerified: Bool
    var isEnabled: Bool
    var monitorMin: Int
    var monitorMax: Int
    var lightMinPercent: Int
    var lightMaxPercent: Int
    var deviceInfo: WiZDeviceInfo?
    private var savedIPAddress: String
    private var discoveredDestination: LightConfiguration?

    init(
        id: UUID = UUID(),
        name: String = "",
        macAddress: String? = nil,
        ip: String = "",
        isIPAddressVerified: Bool = true,
        isEnabled: Bool = false,
        monitorMin: Int = 40,
        monitorMax: Int = 80,
        lightMinPercent: Int = 1,
        lightMaxPercent: Int = 100,
        deviceInfo: WiZDeviceInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.macAddress = macAddress
        self.ip = ip
        savedIPAddress = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isIPAddressVerified = isIPAddressVerified
        self.isEnabled = isEnabled
        self.monitorMin = monitorMin
        self.monitorMax = monitorMax
        self.lightMinPercent = lightMinPercent
        self.lightMaxPercent = lightMaxPercent
        self.deviceInfo = deviceInfo
    }

    init(configuration: LightConfiguration) {
        id = configuration.id
        name = configuration.name
        macAddress = configuration.macAddress
        ip = configuration.ip
        savedIPAddress = configuration.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        isIPAddressVerified = configuration.isIPAddressVerified
        isEnabled = configuration.isEnabled
        monitorMin = Int(configuration.mapping.monitorMin.rounded())
        monitorMax = Int(configuration.mapping.monitorMax.rounded())
        lightMinPercent = Int(
            configuration.mapping.lightMinPercent.rounded()
        )
        lightMaxPercent = Int(
            configuration.mapping.lightMaxPercent.rounded()
        )
        deviceInfo = configuration.deviceInfo
    }

    private var normalizedIPAddress: String {
        ip.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasManualAddressEdit: Bool {
        macAddress == nil && normalizedIPAddress != savedIPAddress
    }

    mutating func mergeDiscoveryChanges(_ saved: LightConfiguration) {
        let preservesManualAddress = hasManualAddressEdit &&
            normalizedIPAddress != saved.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        savedIPAddress = saved.ip.trimmingCharacters(in: .whitespacesAndNewlines)

        // Do not associate an old address's discovered identity with a new manual address.
        // Advance the saved baseline even for our own saves, so later replies can merge.
        guard !preservesManualAddress else { return }
        macAddress = saved.macAddress
        ip = saved.ip
        isIPAddressVerified = saved.isIPAddressVerified
        deviceInfo = saved.deviceInfo
    }

    static func mergeDiscoveryChanges(_ savedLights: [LightConfiguration], into drafts: inout [LightDraft]) {
        // Rebuild pending identities from the latest snapshot, so an address that
        // becomes unverified or changes again cannot leave stale identity behind.
        for index in drafts.indices {
            drafts[index].discoveredDestination = nil
        }
        for saved in savedLights {
            if let index = drafts.firstIndex(where: { $0.id == saved.id }) {
                drafts[index].mergeDiscoveryChanges(saved)
            }
        }
        for saved in savedLights where !drafts.contains(where: { $0.id == saved.id }) {
            let matchingDrafts = drafts.indices.filter {
                drafts[$0].hasManualAddressEdit && drafts[$0].normalizedIPAddress == saved.ip
            }
            if saved.isIPAddressVerified, saved.macAddress != nil,
               matchingDrafts.count == 1, let index = matchingDrafts.first {
                // Keep the manual row's ID and edits. Its next save adopts the
                // identity found at the edited destination instead of duplicating it.
                drafts[index].discoveredDestination = saved
            } else {
                drafts.append(LightDraft(configuration: saved))
            }
        }
    }

    static func configurationsForSaving(_ drafts: [LightDraft]) -> [LightConfiguration] {
        var configurations = drafts.map(\.configuration)
        for draft in drafts {
            // If the user edits away from a reconciled destination before saving,
            // retain that discovered light separately instead of silently dropping it.
            if let destination = draft.discoveredDestination,
               !configurations.contains(where: {
                   $0.id == destination.id || $0.macAddress == destination.macAddress
               }) {
                configurations.append(destination)
            }
        }
        return configurations
    }

    var configuration: LightConfiguration {
        let destination = discoveredDestination.flatMap {
            macAddress == nil && $0.ip == normalizedIPAddress ? $0 : nil
        }
        return LightConfiguration(
            id: id,
            name: name,
            macAddress: destination?.macAddress ?? macAddress,
            ip: ip,
            isIPAddressVerified: destination?.isIPAddressVerified ?? isIPAddressVerified,
            isEnabled: isEnabled,
            port: 38899,
            mapping: BrightnessMapping(
                monitorMin: Double(monitorMin),
                monitorMax: Double(monitorMax),
                lightMinPercent: Double(lightMinPercent),
                lightMaxPercent: Double(lightMaxPercent)
            ),
            deviceInfo: destination?.deviceInfo ?? deviceInfo
        )
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Unnamed Light" : trimmedName
    }
}
