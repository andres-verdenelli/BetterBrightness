#if DEBUG
import SwiftUI

struct DebugDiagnosticsView: View {
    @ObservedObject var controller: BrightnessController
    @ObservedObject var store: ConfigurationStore
    let simulated: Bool

    var body: some View {
        Form {
            Section("Current state") {
                LabeledContent("Mode", value: simulated ? "Simulated · no device control" : "Real lights")
                LabeledContent("Monitor", value: String(store.configuration.monitor.displayID))
                LabeledContent("Last brightness", value: controller.lastMonitorBrightness.map { String(format: "%.0f%%", $0) } ?? "No brightness received")
                LabeledContent("Pause", value: controller.isPaused ? "Paused" : "Active")
            }
            Section {
                if controller.menuDestinations.isEmpty { Text("No menu destinations configured.") }
                ForEach(controller.menuDestinations, id: \.id) { destination in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(destination.name).font(.headline)
                        LabeledContent("Sync", value: controller.syncEnabled(for: destination.id) ? "On" : "Off")
                        LabeledContent("Offset", value: String(format: "%+d", controller.offset(for: destination.id)))
                        LabeledContent("Status", value: controller.disabledReason(for: destination.id) ?? "Ready")
                    }
                    .textSelection(.enabled)
                }
            } header: { Text("Menu destinations") } footer: {
                Text("Ready means commands can be sent. It does not confirm physical lamp brightness. This view shows current state; it keeps no event history.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 360)
    }
}
#endif
