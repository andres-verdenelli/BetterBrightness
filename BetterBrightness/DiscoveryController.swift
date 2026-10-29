import Combine
import Foundation

/// Owns discovery independently of Settings, including the launch scan.
@MainActor
final class DiscoveryController: ObservableObject {
    typealias Discover = @MainActor (
        DiscoveryConfiguration,
        @escaping (Int) -> Void,
        @escaping (Result<[DiscoveredWiZLight], Error>) -> Void
    ) -> Void

    @Published private(set) var isDiscovering = false
    @Published private(set) var attempt = 0
    @Published private(set) var totalAttempts = 0
    @Published private(set) var lastSummary: DiscoveryMergeSummary?
    @Published private(set) var errorMessage: String?

    private let configurationStore: ConfigurationStore
    private let discover: Discover

    init(
        configurationStore: ConfigurationStore,
        discover: @escaping Discover = { configuration, onAttempt, completion in
            WiZDiscoveryService.discover(
                configuration: configuration,
                onAttempt: onAttempt,
                completion: completion
            )
        }
    ) {
        self.configurationStore = configurationStore
        self.discover = discover
    }

    func discoverLights() {
        guard !isDiscovering else { return }

        let configuration = configurationStore.configuration.discovery
        attempt = 0
        totalAttempts = configuration.attemptCount
        lastSummary = nil
        errorMessage = nil
        isDiscovering = true

        discover(configuration, { [weak self] attempt in
            self?.attempt = attempt
        }, { [weak self] result in
            guard let self else { return }
            defer { self.isDiscovering = false }

            do {
                self.lastSummary = try self.configurationStore
                    .applyDiscoveryResults(result.get())
            } catch {
                self.errorMessage = error.localizedDescription
            }
        })
    }
}
