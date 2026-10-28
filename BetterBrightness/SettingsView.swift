import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var configurationStore: ConfigurationStore

    @State private var displayIDText: String
    @State private var discoveryResponseWindowText: String
    @State private var discoveryAttemptCountText: String
    @State private var lights: [LightDraft]
    @State private var selectedLightID: UUID?
    @State private var showsAdvanced = false
    @State private var errorMessage = ""
    @State private var showsError = false
    @State private var lightPendingDeletion: LightDraft?
    @State private var showsDeleteConfirmation = false
    @State private var renamingLightID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFocus: UUID?
    @FocusState private var advancedField: AdvancedField?

    private enum AdvancedField: Hashable {
        case displayID, responseWindow, attempts
    }

    init(configurationStore: ConfigurationStore) {
        self.configurationStore = configurationStore
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
        NavigationSplitView {
            List(selection: selectionBinding) {
                Section("Lights") {
                    ForEach(sortedLightIDs, id: \.self) { id in
                        if let light = lights.first(where: { $0.id == id }) {
                            sidebarRow(light)
                                .tag(id)
                                .onTapGesture(count: 2) { beginRename(id) }
                                .contextMenu {
                                    Button("Rename") { beginRename(id) }
                                    Button("Remove Light…", role: .destructive) {
                                        requestRemoval(light)
                                    }
                                    .disabled(lights.count <= 1)
                                }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            if let id = selectedLightID,
               let index = lights.firstIndex(where: { $0.id == id }) {
                LightDetailView(
                    light: $lights[index],
                    onCommit: {
                        // A selection change has already committed the previous draft.
                        guard selectedLightID == id else { return }
                        saveConfiguration()
                    }
                )
                .id(id)
            } else {
                ContentUnavailableView("Select a Light", systemImage: "lightbulb")
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Add Light Manually", systemImage: "plus") {
                    finishRename()
                    guard saveConfiguration() else { return }
                    let light = LightDraft()
                    lights.append(light)
                    selectedLightID = light.id
                    beginRename(light.id)
                }
                .help("Add a light by IP address")

                Button("Advanced Settings", systemImage: "gearshape") {
                    finishRename()
                    guard saveConfiguration() else { return }
                    showsAdvanced = true
                }
                .help("Monitor and discovery settings")
            }
        }
        .background {
            SettingsFocusMonitor { advancedField = nil }
        }
        .onReceive(configurationStore.$configuration) { configuration in
            mergeDiscoveryChangesIntoDrafts(configuration)
        }
        .onChange(of: renameFocus) { previous, current in
            if let previous, previous != current, previous == renamingLightID {
                finishRename()
            }
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: light.isIPAddressVerified ? "lightbulb" : "exclamationmark.triangle")
                .foregroundStyle(light.isIPAddressVerified ? Color.secondary : Color.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if renamingLightID == light.id {
                    TextField("Light name", text: $renameText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color(nsColor: .textColor))
                        .tint(Color(nsColor: .controlAccentColor))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .focused($renameFocus, equals: light.id)
                        .onSubmit(finishRename)
                        .onExitCommand(perform: cancelRename)
                        .onAppear { renameFocus = light.id }
                } else {
                    Text(light.displayName)
                        .lineLimit(1)
                        .help(light.displayName)
                }
                Text(light.isIPAddressVerified
                     ? (light.ip.isEmpty ? "Enter an IP address" : light.ip)
                     : "Waiting for rediscovery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        renameFocus = nil
        // A manually added light can be named before its IP address is entered.
        if !lights[index].ip.isEmpty { saveConfiguration() }
    }

    private func cancelRename() {
        renamingLightID = nil
        renameFocus = nil
    }

    private var advancedSettings: some View {
        VStack(spacing: 0) {
            Form {
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
                    Text("Default: 500 ms and 3 attempts. Longer windows and more attempts make discovery take longer. Discover lights from the menu bar.")
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
        .frame(width: 460, height: 360)
        .background {
            SettingsFocusMonitor { advancedField = nil }
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
        for saved in configuration.lights {
            if let index = lights.firstIndex(where: { $0.id == saved.id }) {
                lights[index].mergeDiscoveryChanges(saved)
            } else {
                lights.append(LightDraft(configuration: saved))
            }
        }
    }

    private func requestRemoval(_ light: LightDraft) {
        cancelRename()
        lightPendingDeletion = light
        showsDeleteConfirmation = true
    }

    private func removeLight(_ id: UUID) {
        guard lights.count > 1 else { return }
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

private struct SettingsFocusMonitor: NSViewRepresentable {
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
    let onCommit: () -> Void
    @FocusState private var isIPFocused: Bool

    private let syncHelp = "When on, this light follows brightness changes from your selected BetterDisplay monitor. Turn it off to stop sending brightness updates to this light."

    private var mappingHelp: String {
        "Monitor chooses the brightness range that controls this light. Light chooses how dim and how bright the light can get. These controls do not change your monitor's brightness.\n\n"
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
                rangeRow("Monitor", minimum: $light.monitorMin,
                         maximum: $light.monitorMax, domain: 0...100)
                rangeRow("Light", minimum: $light.lightMinPercent,
                         maximum: $light.lightMaxPercent, domain: 1...100)
            } header: {
                HStack {
                    Text("Brightness mapping")
                    Spacer()
                    SettingsHelpButton(title: "Brightness mapping", explanation: mappingHelp)
                }
            }

            Section("Light") {
                if light.macAddress == nil {
                    TextField("IP address", text: $light.ip)
                        .focused($isIPFocused)
                        .onSubmit(onCommit)
                        .help("Discover lights from the menu bar to identify this light by MAC address.")
                } else {
                    LabeledContent("IP address", value: light.ip)
                    if let mac = light.macAddress {
                        LabeledContent("MAC address", value: WiZMACAddress.display(mac))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(light.displayName)
        .onChange(of: isIPFocused) { previous, current in
            if previous && !current { onCommit() }
        }
    }

    private func rangeRow(
        _ title: String, minimum: Binding<Int>, maximum: Binding<Int>,
        domain: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.medium))
            HStack(spacing: 12) {
                Text("\(minimum.wrappedValue)%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
                    .accessibilityLabel("\(title) minimum: \(minimum.wrappedValue) percent")
                BrightnessRangeControl(minimum: minimum, maximum: maximum,
                                       domain: domain, title: title, onCommit: onCommit)
                    .frame(height: 28)
                Text("\(maximum.wrappedValue)%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
                    .accessibilityLabel("\(title) maximum: \(maximum.wrappedValue) percent")
            }
        }
        .padding(.vertical, 4)
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
