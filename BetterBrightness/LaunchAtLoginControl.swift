import AppKit
import ServiceManagement
import SwiftUI

struct LaunchAtLoginControl: View {
    @ObservedObject var controller: LaunchAtLoginController
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at Login", isOn: Binding(
                get: { controller.isRequested },
                set: { enabled in
                    do {
                        try controller.setEnabled(enabled)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            ))
            .toggleStyle(.switch)
            .help("Open BetterBrightness in the menu bar when you log in to your Mac.")

            if controller.status == .requiresApproval {
                Text("Approval required in System Settings before BetterBrightness can launch at login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Login Items Settings…") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else if controller.status == .notFound {
                Text("Login item unavailable. Move BetterBrightness to Applications and try again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { controller.refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            controller.refresh()
        }
        .alert("Unable to Change Launch at Login", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
