import Darwin
import Foundation

struct DiscoveredWiZLight: Sendable {
    let macAddress: String
    let ipAddress: String
    let deviceInfo: WiZDeviceInfo
}

struct DiscoveryMergeSummary {
    let foundLights: Int
    let newLights: Int
    let updatedIPs: Int
    let identifiedExistingLights: Int
    let invalidatedIPs: Int
}

enum WiZMACAddress {
    static func normalized(_ value: String) -> String? {
        let hexadecimalCharacters = value
            .lowercased()
            .filter { $0.isHexDigit }

        guard hexadecimalCharacters.count == 12 else { return nil }
        return hexadecimalCharacters
    }

    static func display(_ value: String) -> String {
        guard let normalized = normalized(value) else { return value }

        return stride(from: 0, to: normalized.count, by: 2)
            .map { offset in
                let start = normalized.index(normalized.startIndex, offsetBy: offset)
                let end = normalized.index(start, offsetBy: 2)
                return String(normalized[start..<end]).uppercased()
            }
            .joined(separator: ":")
    }
}

enum WiZDiscoveryError: LocalizedError {
    case discoveryAlreadyRunning
    case couldNotCreateSocket(String)
    case couldNotConfigureSocket(String)
    case couldNotBindSocket(String)
    case couldNotCreateBroadcastAddress
    case couldNotSendBroadcast(String)

    var errorDescription: String? {
        switch self {
        case .discoveryAlreadyRunning:
            return "A WiZ discovery run is already in progress."
        case .couldNotCreateSocket(let reason):
            return "Could not create the UDP discovery socket: \(reason)"
        case .couldNotConfigureSocket(let reason):
            return "Could not enable UDP broadcast: \(reason)"
        case .couldNotBindSocket(let reason):
            return "Could not bind the UDP discovery socket: \(reason)"
        case .couldNotCreateBroadcastAddress:
            return "Could not create the WiZ broadcast address."
        case .couldNotSendBroadcast(let reason):
            return "Could not send the WiZ discovery message: \(reason)"
        }
    }
}

enum WiZDiscoveryService {
    private static var isDiscovering = false

    @MainActor
    static func discover(
        configuration: DiscoveryConfiguration,
        onAttempt: @escaping (Int) -> Void,
        completion: @escaping (Result<[DiscoveredWiZLight], Error>) -> Void
    ) {
        guard !isDiscovering else {
            completion(.failure(WiZDiscoveryError.discoveryAlreadyRunning))
            return
        }
        isDiscovering = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<[DiscoveredWiZLight], Error>

            do {
                let lights = try performDiscovery(
                    configuration: configuration
                ) { attempt in
                    DispatchQueue.main.async {
                        onAttempt(attempt)
                    }
                }
                result = .success(lights)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                isDiscovering = false
                completion(result)
            }
        }
    }

    private static func performDiscovery(
        configuration: DiscoveryConfiguration,
        onAttempt: (Int) -> Void
    ) throws -> [DiscoveredWiZLight] {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else {
            throw WiZDiscoveryError.couldNotCreateSocket(lastSocketError())
        }
        defer { Darwin.close(socketDescriptor) }

        var enabled: Int32 = 1
        guard setsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_BROADCAST,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw WiZDiscoveryError.couldNotConfigureSocket(lastSocketError())
        }

        var localAddress = sockaddr_in()
        localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        localAddress.sin_family = sa_family_t(AF_INET)
        localAddress.sin_port = 0
        localAddress.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &localAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    socketDescriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0 else {
            throw WiZDiscoveryError.couldNotBindSocket(lastSocketError())
        }

        var broadcastAddress = sockaddr_in()
        broadcastAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        broadcastAddress.sin_family = sa_family_t(AF_INET)
        broadcastAddress.sin_port = in_port_t(38899).bigEndian

        let addressResult = "255.255.255.255".withCString {
            inet_pton(AF_INET, $0, &broadcastAddress.sin_addr)
        }
        guard addressResult == 1 else {
            throw WiZDiscoveryError.couldNotCreateBroadcastAddress
        }

        let message = Data(
            #"{"method":"getSystemConfig","params":{}}"#.utf8
        )
        var discoveredByMAC: [String: DiscoveredWiZLight] = [:]

        for attempt in 1...configuration.attemptCount {
            onAttempt(attempt)
            try send(
                message,
                socketDescriptor: socketDescriptor,
                destination: &broadcastAddress
            )
            receiveResponses(
                socketDescriptor: socketDescriptor,
                timeoutMilliseconds: configuration.responseWindowMilliseconds,
                discoveredByMAC: &discoveredByMAC
            )
        }

        return discoveredByMAC.values.sorted {
            $0.macAddress < $1.macAddress
        }
    }

    private static func send(
        _ data: Data,
        socketDescriptor: Int32,
        destination: inout sockaddr_in
    ) throws {
        let sentBytes = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(
                        socketDescriptor,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }

        guard sentBytes == data.count else {
            throw WiZDiscoveryError.couldNotSendBroadcast(lastSocketError())
        }
    }

    private static func receiveResponses(
        socketDescriptor: Int32,
        timeoutMilliseconds: Int,
        discoveredByMAC: inout [String: DiscoveredWiZLight]
    ) {
        let deadline = Date().addingTimeInterval(
            Double(timeoutMilliseconds) / 1_000
        )

        while true {
            let remainingMilliseconds = Int(
                deadline.timeIntervalSinceNow * 1_000
            )
            guard remainingMilliseconds > 0 else { return }

            var descriptor = pollfd(
                fd: socketDescriptor,
                events: Int16(POLLIN),
                revents: 0
            )
            let pollResult = Darwin.poll(
                &descriptor,
                1,
                Int32(remainingMilliseconds)
            )

            guard pollResult > 0 else { return }
            guard descriptor.revents & Int16(POLLIN) != 0 else { continue }

            if let light = receiveLight(socketDescriptor: socketDescriptor) {
                discoveredByMAC[light.macAddress] = light
            }
        }
    }

    private static func receiveLight(
        socketDescriptor: Int32
    ) -> DiscoveredWiZLight? {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        var sourceAddress = sockaddr_in()
        var sourceAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)

        let receivedBytes = buffer.withUnsafeMutableBytes { bytes in
            withUnsafeMutablePointer(to: &sourceAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(
                        socketDescriptor,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        $0,
                        &sourceAddressLength
                    )
                }
            }
        }

        guard receivedBytes > 0 else { return nil }

        let responseData = Data(buffer.prefix(receivedBytes))
        guard let response = decodeResponse(responseData) else { return nil }
        guard let macAddress = WiZMACAddress.normalized(response.result.mac) else {
            return nil
        }
        guard let ipAddress = ipAddress(from: sourceAddress) else { return nil }

        return DiscoveredWiZLight(
            macAddress: macAddress,
            ipAddress: ipAddress,
            deviceInfo: WiZDeviceInfo(
                moduleName: response.result.moduleName,
                firmwareVersion: response.result.firmwareVersion,
                homeID: response.result.homeID,
                roomID: response.result.roomID,
                region: response.result.region
            )
        )
    }

    private static func decodeResponse(
        _ data: Data
    ) -> WiZSystemConfigResponse? {
        guard
            let firstBrace = data.firstIndex(of: UInt8(ascii: "{")),
            let lastBrace = data.lastIndex(of: UInt8(ascii: "}")),
            firstBrace <= lastBrace
        else {
            return nil
        }

        return try? JSONDecoder().decode(
            WiZSystemConfigResponse.self,
            from: data[firstBrace...lastBrace]
        )
    }

    private static func ipAddress(from address: sockaddr_in) -> String? {
        var address = address.sin_addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

        guard inet_ntop(
            AF_INET,
            &address,
            &buffer,
            socklen_t(INET_ADDRSTRLEN)
        ) != nil else {
            return nil
        }

        return String(cString: buffer)
    }

    private static func lastSocketError() -> String {
        String(cString: strerror(errno))
    }
}

private struct WiZSystemConfigResponse: Decodable {
    let result: Result

    struct Result: Decodable {
        let mac: String
        let moduleName: String?
        let firmwareVersion: String?
        let homeID: Int?
        let roomID: Int?
        let region: String?

        private enum CodingKeys: String, CodingKey {
            case mac
            case moduleName
            case firmwareVersion = "fwVersion"
            case homeID = "homeId"
            case roomID = "roomId"
            case region = "rgn"
        }
    }
}
