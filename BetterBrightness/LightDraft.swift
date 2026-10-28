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

    mutating func mergeDiscoveryChanges(_ saved: LightConfiguration) {
        let hasManualAddressEdit = macAddress == nil &&
            ip.trimmingCharacters(in: .whitespacesAndNewlines) != savedIPAddress
        savedIPAddress = saved.ip.trimmingCharacters(in: .whitespacesAndNewlines)

        // Do not associate an old address's discovered identity with a new manual address.
        // Advance the saved baseline even for our own saves, so later replies can merge.
        guard !hasManualAddressEdit else { return }
        macAddress = saved.macAddress
        ip = saved.ip
        isIPAddressVerified = saved.isIPAddressVerified
        deviceInfo = saved.deviceInfo
    }

    var configuration: LightConfiguration {
        LightConfiguration(
            id: id,
            name: name,
            macAddress: macAddress,
            ip: ip,
            isIPAddressVerified: isIPAddressVerified,
            isEnabled: isEnabled,
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
