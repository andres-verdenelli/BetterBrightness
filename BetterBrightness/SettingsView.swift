import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var configurationStore: ConfigurationStore
    @ObservedObject var discovery: DiscoveryController
    @ObservedObject var launchAtLogin: LaunchAtLoginController

    @State private var displayIDText: String
    @State private var discoveryResponseWindowText: String
    @State private var discoveryAttemptCountText: String
    @State private var lights: [LightDraft]
    @State private var selectedLightID: UUID?
    @State private var isSidebarVisible = true
    @State private var showsAdvanced = false
    @State private var errorMessage = ""
    @State private var showsError = false
    @State private var lightPendingDeletion: LightDraft?
    @State private var showsDeleteConfirmation = false
    @State private var renamingLightID: UUID?
    @State private var renameText = ""
    @FocusState private var advancedField: AdvancedField?

    private enum AdvancedField: Hashable {
        case displayID, responseWindow, attempts
    }

    init(configurationStore: ConfigurationStore, discovery: DiscoveryController, launchAtLogin: LaunchAtLoginController) {
        self.configurationStore = configurationStore
        self.discovery = discovery
        self.launchAtLogin = launchAtLogin
        let configuration = configurationStore.configuration
        _displayIDText = State(initialValue: String(configuration.monitor.displayID))
        _discoveryResponseWindowText = State(
            initialValue: String(configuration.discovery.responseWindowMilliseconds)
        )
        _discoveryAttemptCountText = State(
            initialValue: String(configuration.discovery.attemptCount)
        )
        _lights = State(initialValue: configuration.lights.map { LightDraft(configuration: $0) })
        _selectedLightID = State(initialValue:
            configuration.lights.first(where: \.isEnabled)?.id
                ?? configuration.lights.first?.id
        )
    }

    var body: some View {
        SettingsSplitView(isSidebarVisible: $isSidebarVisible) {
            List(selection: selectionBinding) {
                Section("Lights") {
                    ForEach(sortedLightIDs, id: \.self) { id in
                        if let light = lights.first(where: { $0.id == id }) {
                            sidebarRow(light)
                                .tag(id)
                                .contextMenu {
                                    Button("Remove Light…", role: .destructive) {
                                        requestRemoval(light)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        } detail: {
            if let id = selectedLightID,
               let index = lights.firstIndex(where: { $0.id == id }) {
                LightDetailView(
                    light: $lights[index],
                    isRenaming: renamingLightID == id,
                    renameText: $renameText,
                    onBeginRename: { beginRename(id) },
                    onFinishRename: finishRename,
                    onCancelRename: cancelRename,
                    onCommit: {
                        // A selection change has already committed the previous draft.
                        guard selectedLightID == id else { return }
                        saveConfiguration()
                    }
                )
                .id(id)
            } else {
                ContentUnavailableView(
                    lights.isEmpty ? "No Lights" : "Select a Light",
                    systemImage: "lightbulb",
                    description: Text("Open Advanced Settings with the gear button, then choose Discover Lights to find lights on your network.")
                )
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle(lights.first(where: { $0.id == selectedLightID })?.displayName ?? "Settings")
        .toolbar {
            ToolbarItem(id: "sidebarToggle", placement: .navigation) {
                Button(
                    isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                    systemImage: "sidebar.left"
                ) {
                    withAnimation {
                        isSidebarVisible.toggle()
                    }
                }
                .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }
            ToolbarItemGroup {
                Button("Advanced Settings", systemImage: "gearshape") {
                    finishRename()
                    guard saveConfiguration() else { return }
                    showsAdvanced = true
                }
                .help("Launch at Login, monitor, and discovery settings")
            }
        }
        .background {
            SettingsWindowSupport { advancedField = nil }
        }
        .onReceive(configurationStore.$configuration) { configuration in
            mergeDiscoveryChangesIntoDrafts(configuration)
        }
        .sheet(isPresented: $showsAdvanced) {
            advancedSettings
        }
        .alert("Unable to Save", isPresented: Binding(
            get: { showsError && !showsAdvanced },
            set: { showsError = $0 }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Remove Light?", isPresented: $showsDeleteConfirmation,
               presenting: lightPendingDeletion) { light in
            Button("Remove", role: .destructive) { removeLight(light.id) }
            Button("Cancel", role: .cancel) {}
        } message: { light in
            Text("\(light.displayName) will be removed from BetterBrightness.")
        }
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(get: { selectedLightID }, set: { id in
            finishRename()
            guard id != selectedLightID, saveConfiguration() else { return }
            selectedLightID = id
        })
    }

    private func sidebarRow(_ light: LightDraft) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: light.isIPAddressVerified ? "lightbulb" : "exclamationmark.triangle")
                .foregroundStyle(light.isIPAddressVerified ? Color.secondary : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(light.displayName)
                    .lineLimit(1)
                    .help(light.displayName)
                if !light.isIPAddressVerified {
                    Text("Waiting for rediscovery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private var sortedLightIDs: [UUID] {
        lights.sorted { first, second in
            if first.isEnabled != second.isEnabled { return first.isEnabled }
            let comparison = first.displayName.localizedStandardCompare(second.displayName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return first.id.uuidString < second.id.uuidString
        }.map(\.id)
    }

    private func beginRename(_ id: UUID) {
        guard renamingLightID != id,
              let light = lights.first(where: { $0.id == id }) else { return }
        finishRename()
        if selectedLightID != id {
            guard saveConfiguration() else { return }
            selectedLightID = id
        }
        renameText = light.name
        renamingLightID = id
    }

    private func finishRename() {
        guard let id = renamingLightID,
              let index = lights.firstIndex(where: { $0.id == id }) else { return }
        lights[index].name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingLightID = nil
        saveConfiguration()
    }

    private func cancelRename() {
        renamingLightID = nil
    }

    private var advancedSettings: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LaunchAtLoginControl(controller: launchAtLogin)
                }
                Section {
                    TextField("BetterDisplay display ID", text: displayIDBinding)
                        .focused($advancedField, equals: .displayID)
                        .onSubmit(saveDisplayIDIfNeeded)
                } header: {
                    Text("Monitor")
                } footer: {
                    Text("Use the displayID shown in BetterDisplay brightness notifications.")
                }
                Section {
                    DiscoverySettingsContent(discovery: discovery) {
                        guard saveConfiguration() else { return }
                        discovery.discoverLights()
                    }
                    LabeledContent("Response window") {
                        HStack(spacing: 4) {
                            TextField("Response window", text: discoveryResponseWindowBinding)
                                .labelsHidden()
                                .frame(width: 65)
                                .multilineTextAlignment(.trailing)
                                .focused($advancedField, equals: .responseWindow)
                                .onSubmit(saveDiscoverySettingsIfNeeded)
                            Text("ms").foregroundStyle(.secondary)
                        }
                    }
                    TextField("Attempts", text: discoveryAttemptCountBinding)
                        .focused($advancedField, equals: .attempts)
                        .onSubmit(saveDiscoverySettingsIfNeeded)
                } header: {
                    Text("Discovery")
                } footer: {
                    Text("Default: 500 ms and 3 attempts. Longer windows and more attempts make discovery take longer. Use Discover Lights above to search your network.")
                }
            }
            .formStyle(.grouped)
            .monospacedDigit()
            HStack {
                Spacer()
                Button("Done") {
                    guard saveConfiguration() else { return }
                    showsAdvanced = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 640)
        .background {
            SettingsWindowSupport { advancedField = nil }
        }
        .onChange(of: advancedField) { previous, _ in
            if previous == .displayID { saveDisplayIDIfNeeded() }
            if previous == .responseWindow || previous == .attempts {
                saveDiscoverySettingsIfNeeded()
            }
        }
        .alert("Unable to Save", isPresented: $showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    @discardableResult
    private func saveConfiguration() -> Bool {
        guard
            let displayID = Int(displayIDText),
            displayID > 0
        else {
            showInvalidDisplayIDError()
            return false
        }

        guard let discoveryConfiguration = validatedDiscoveryConfiguration()
        else { return false }

        do {
            try configurationStore.save(
                displayID: displayID,
                lights: lights.map(\.configuration),
                discovery: discoveryConfiguration
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            showsError = true
            return false
        }
    }

    private func saveDisplayIDIfNeeded() {
        let savedDisplayID = configurationStore.configuration.monitor.displayID

        guard
            let displayID = Int(displayIDText),
            displayID > 0
        else {
            displayIDText = String(savedDisplayID)
            showInvalidDisplayIDError()
            return
        }

        displayIDText = String(displayID)
        guard displayID != savedDisplayID else { return }

        saveConfiguration()
    }

    private var displayIDBinding: Binding<String> {
        Binding(
            get: { displayIDText },
            set: { newValue in
                displayIDText = newValue.filter(\.isNumber)
            }
        )
    }

    private var discoveryResponseWindowBinding: Binding<String> {
        Binding(
            get: { discoveryResponseWindowText },
            set: { newValue in
                discoveryResponseWindowText = newValue.filter(\.isNumber)
            }
        )
    }

    private var discoveryAttemptCountBinding: Binding<String> {
        Binding(
            get: { discoveryAttemptCountText },
            set: { newValue in
                discoveryAttemptCountText = newValue.filter(\.isNumber)
            }
        )
    }

    private func showInvalidDisplayIDError() {
        errorMessage = ConfigurationError.invalidDisplayID.localizedDescription
        showsError = true
    }

    private func validatedDiscoveryConfiguration(
        restoreInvalidValue: Bool = false
    ) -> DiscoveryConfiguration? {
        let savedConfiguration = configurationStore.configuration.discovery

        guard
            let responseWindow = Int(discoveryResponseWindowText),
            DiscoveryConfiguration.responseWindowRange.contains(responseWindow)
        else {
            if restoreInvalidValue {
                discoveryResponseWindowText = String(
                    savedConfiguration.responseWindowMilliseconds
                )
            }
            errorMessage = ConfigurationError
                .invalidDiscoveryResponseWindow
                .localizedDescription
            showsError = true
            return nil
        }

        guard
            let attemptCount = Int(discoveryAttemptCountText),
            DiscoveryConfiguration.attemptCountRange.contains(attemptCount)
        else {
            if restoreInvalidValue {
                discoveryAttemptCountText = String(
                    savedConfiguration.attemptCount
                )
            }
            errorMessage = ConfigurationError
                .invalidDiscoveryAttemptCount
                .localizedDescription
            showsError = true
            return nil
        }

        discoveryResponseWindowText = String(responseWindow)
        discoveryAttemptCountText = String(attemptCount)
        return DiscoveryConfiguration(
            responseWindowMilliseconds: responseWindow,
            attemptCount: attemptCount
        )
    }

    private func saveDiscoverySettingsIfNeeded() {
        guard let discoveryConfiguration = validatedDiscoveryConfiguration(
            restoreInvalidValue: true
        ) else { return }

        guard discoveryConfiguration != configurationStore.configuration.discovery
        else { return }

        saveConfiguration()
    }

    private func mergeDiscoveryChangesIntoDrafts(_ configuration: AppConfiguration) {
        LightDraft.mergeDiscoveryChanges(configuration.lights, into: &lights)
    }

    private func requestRemoval(_ light: LightDraft) {
        cancelRename()
        lightPendingDeletion = light
        showsDeleteConfirmation = true
    }

    private func removeLight(_ id: UUID) {
        guard let removedIndex = lights.firstIndex(where: { $0.id == id }) else { return }
        let removed = lights.remove(at: removedIndex)
        guard saveConfiguration() else {
            lights.insert(removed, at: removedIndex)
            return
        }
        if selectedLightID == id { selectedLightID = sortedLightIDs.first }
        lightPendingDeletion = nil
    }
}

private struct SettingsWindowSupport: NSViewRepresentable {
    let onDismissFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismissFocus: onDismissFocus)
    }

    func makeNSView(context: Context) -> FocusMonitorView {
        let view = FocusMonitorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: FocusMonitorView, context: Context) {
        context.coordinator.onDismissFocus = onDismissFocus
        context.coordinator.install(in: nsView.window)
    }

    static func dismantleNSView(
        _ nsView: FocusMonitorView,
        coordinator: Coordinator
    ) {
        coordinator.uninstall()
    }

    final class FocusMonitorView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.install(in: window)
        }
    }

    final class Coordinator {
        var onDismissFocus: () -> Void

        private weak var monitoredWindow: NSWindow?
        private var eventMonitor: Any?
        private var didClearInitialFocus = false

        init(onDismissFocus: @escaping () -> Void) {
            self.onDismissFocus = onDismissFocus
        }

        func install(in window: NSWindow?) {
            guard let window else { return }

            if monitoredWindow !== window {
                uninstall()
                monitoredWindow = window
                didClearInitialFocus = false

                // Configure each window once, without reapplying during view updates.
                // Settings scenes can override SwiftUI's scene-level toolbar style.
                window.toolbarStyle = .unified
                window.styleMask.insert(.fullSizeContentView)
            }

            if eventMonitor == nil {
                eventMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: .leftMouseDown
                ) { [weak self] event in
                    self?.handleMouseDown(event)
                    return event
                }
            }

            guard !didClearInitialFocus else { return }
            didClearInitialFocus = true

            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                window.makeFirstResponder(nil)
                onDismissFocus()
            }
        }

        func uninstall() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            monitoredWindow = nil
        }

        private func handleMouseDown(_ event: NSEvent) {
            guard
                let window = monitoredWindow,
                event.window === window,
                let contentView = window.contentView
            else {
                return
            }

            let clickedView = contentView.hitTest(event.locationInWindow)
            guard !isTextInput(clickedView) else { return }

            window.makeFirstResponder(nil)
            onDismissFocus()
        }

        private func isTextInput(_ view: NSView?) -> Bool {
            var candidate = view

            while let currentView = candidate {
                if currentView is NSTextField || currentView is NSTextView {
                    return true
                }
                candidate = currentView.superview
            }

            return false
        }
    }
}

private struct LightDetailView: View {
    @Binding var light: LightDraft
    let isRenaming: Bool
    @Binding var renameText: String
    let onBeginRename: () -> Void
    let onFinishRename: () -> Void
    let onCancelRename: () -> Void
    let onCommit: () -> Void
    @FocusState private var isNameFocused: Bool

    private let syncHelp = "When on, this light follows brightness changes from your selected BetterDisplay monitor. Turn it off to stop sending brightness updates to this light."

    private var mappingHelp: String {
        "Edit the percentages in Dim light and Bright light. Use Tab to reach each percentage; type a value and press Return, or use the stepper to adjust by 1%. Minimum and maximum values stay at least 1 percentage point apart. These controls do not change your monitor's brightness.\n\n"
            + "With your current settings:\n"
            + "• At \(light.monitorMin)% monitor brightness, the light is set to \(light.lightMinPercent)%.\n"
            + "• At \(light.monitorMax)% monitor brightness, the light is set to \(light.lightMaxPercent)%.\n\n"
            + "Between those points, the light changes proportionally: halfway through the monitor range means halfway through the light range. Below or above the monitor range, the light stays at its chosen minimum or maximum."
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Text("Sync brightness")
                    Spacer()
                    SettingsHelpButton(title: "Sync brightness", explanation: syncHelp)
                    Toggle("Sync brightness", isOn: $light.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: light.isEnabled) { onCommit() }
                }
            } footer: {
                if !light.isIPAddressVerified {
                    Label("No commands are sent until this light is rediscovered.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                FollowBrightnessEditor(
                    monitorMin: $light.monitorMin, monitorMax: $light.monitorMax,
                    lightMin: $light.lightMinPercent, lightMax: $light.lightMaxPercent,
                    onCommit: onCommit
                )
            } header: {
                HStack {
                    Text("Follow monitor brightness")
                    Spacer()
                    SettingsHelpButton(title: "Follow monitor brightness", explanation: mappingHelp)
                }
            }

            Section("Light") {
                LabeledContent("Name") {
                    nameEditor.multilineTextAlignment(.trailing)
                }
                LabeledContent("IP address", value: light.ip)
                if let mac = light.macAddress {
                    LabeledContent("MAC address", value: WiZMACAddress.display(mac))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(light.displayName)
        .onChange(of: isNameFocused) { wasFocused, focused in
            if wasFocused && !focused && isRenaming { onFinishRename() }
        }
    }

    @ViewBuilder
    private var nameEditor: some View {
        if isRenaming {
            TextField("Light name", text: $renameText)
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($isNameFocused)
                .onSubmit(onFinishRename)
                .onExitCommand(perform: onCancelRename)
                .onKeyPress(.escape) {
                    onCancelRename()
                    return .handled
                }
                .onAppear {
                    DispatchQueue.main.async { isNameFocused = true }
                }
                .accessibilityLabel("Light name")
        } else {
            Button(action: onBeginRename) {
                HStack(spacing: 6) {
                    Text(light.displayName).lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rename light")
            .accessibilityLabel("Rename \(light.displayName)")
        }
    }


}

private struct SettingsHelpButton: View {
    let title: String
    let explanation: String
    @State private var isPresented = false
    @State private var isPinned = false

    var body: some View {
        Button {
            if isPinned {
                isPinned = false
                isPresented = false
            } else {
                isPinned = true
                isPresented = true
            }
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) help")
        .onHover { isHovering in
            if isHovering { isPresented = true }
            else if !isPinned { isPresented = false }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                Text(explanation).font(.callout)
            }
            .padding(14)
            .frame(width: 330, alignment: .leading)
        }
        .onChange(of: isPresented) { _, shown in
            if !shown { isPinned = false }
        }
    }
}

struct DiscoverySettingsContent: View {
    @ObservedObject var discovery: DiscoveryController

    let onDiscover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button("Discover Lights", systemImage: "dot.radiowaves.left.and.right") {
                    onDiscover()
                }
                .disabled(discovery.isDiscovering)
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                status
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }

            if !discovery.isDiscovering, let errorMessage = discovery.errorMessage {
                Text(errorMessage)
            } else if !discovery.isDiscovering,
                      let summary = discovery.lastSummary,
                      summary.invalidatedIPs > 0 {
                Text("\(summary.invalidatedIPs) waiting for rediscovery")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var status: some View {
        if discovery.isDiscovering {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(discovery.attempt == 0
                     ? "Starting discovery…"
                     : "Attempt \(discovery.attempt) of \(discovery.totalAttempts)")
            }
        } else if discovery.errorMessage != nil {
            Text("Discovery failed")
        } else if let summary = discovery.lastSummary {
            if summary.foundLights == 0 {
                Text("No WiZ lights found")
            } else if summary.newLights == 0 {
                Text("No new lights found")
            } else {
                Text("\(summary.newLights) new \(summary.newLights == 1 ? "light" : "lights") found")
            }
        }
    }
}
