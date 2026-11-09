import Foundation

struct LightDraft: Identifiable {
    let id: UUID
    var name: String
    private(set) var macAddress: String?
    private(set) var ip: String
    var isIPAddressVerified: Bool
    var isEnabled: Bool
    var isHidden: Bool
    var monitorMin: Int
    var monitorMax: Int
    var lightMinPercent: Int
    var lightMaxPercent: Int
    var deviceInfo: WiZDeviceInfo?

    init(configuration: LightConfiguration) {
        id = configuration.id
        name = configuration.name
        macAddress = configuration.macAddress
        ip = configuration.ip
        isIPAddressVerified = configuration.isIPAddressVerified
        isEnabled = configuration.isEnabled
        isHidden = configuration.isHidden
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

    mutating func mergeDiscoveryChanges(_ saved: LightConfiguration) {
        macAddress = saved.macAddress
        ip = saved.ip
        isIPAddressVerified = saved.isIPAddressVerified
        deviceInfo = saved.deviceInfo
    }

    static func mergeDiscoveryChanges(_ savedLights: [LightConfiguration], into drafts: inout [LightDraft]) {
        for saved in savedLights {
            if let index = drafts.firstIndex(where: { $0.id == saved.id }) {
                drafts[index].mergeDiscoveryChanges(saved)
            } else {
                drafts.append(LightDraft(configuration: saved))
            }
        }
    }

    var configuration: LightConfiguration {
        LightConfiguration(
            id: id,
            name: name,
            macAddress: macAddress,
            ip: ip,
            isIPAddressVerified: isIPAddressVerified,
            isEnabled: isEnabled,
            isHidden: isHidden,
            port: 38899,
            mapping: BrightnessMapping(
                monitorMin: Double(monitorMin),
                monitorMax: Double(monitorMax),
                lightMinPercent: Double(lightMinPercent),
                lightMaxPercent: Double(lightMaxPercent)
            ),
            deviceInfo: deviceInfo
        )
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Unnamed Light" : trimmedName
    }
}
