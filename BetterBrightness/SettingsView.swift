import AppKit
import SwiftUI

private struct LightDraft: Identifiable {
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

struct SettingsView: View {
    @ObservedObject var configurationStore: ConfigurationStore

    @State private var displayIDText: String
    @State private var discoveryResponseWindowText: String
    @State private var discoveryAttemptCountText: String
    @State private var lights: [LightDraft]
    @State private var errorMessage = ""
    @State private var showsError = false
    @State private var lightPendingDeletion: LightDraft?
    @State private var showsDeleteConfirmation = false
    @State private var isDiscovering = false
    @State private var discoveryAttempt = 0
    @State private var discoveryTotalAttempts = 0
    @State private var discoveryResultText: String?
    @State private var showsMonitorHelp = false
    @State private var showsResponseWindowHelp = false
    @State private var showsAttemptCountHelp = false
    @FocusState private var isDisplayIDFocused: Bool
    @FocusState private var isResponseWindowFocused: Bool
    @FocusState private var isAttemptCountFocused: Bool

    private let monitorHelpText =
        "Use the displayID shown in BetterDisplay brightness notifications."
    private let responseWindowHelpText =
        "How long BetterBrightness listens for replies after each discovery " +
        "broadcast. The default is 500 ms. A value between 500 and 1,000 ms " +
        "is recommended; shorter windows can miss slower lights, while longer " +
        "windows make discovery take more time."
    private let attemptCountHelpText =
        "How many discovery broadcasts BetterBrightness sends. The default is " +
        "3 attempts, and 3–5 is usually enough. More attempts improve the chance " +
        "of hearing from every light but take longer. The maximum is 10."

    init(configurationStore: ConfigurationStore) {
        self.configurationStore = configurationStore

        let configuration = configurationStore.configuration
        _displayIDText = State(
            initialValue: String(configuration.monitor.displayID)
        )
        _discoveryResponseWindowText = State(
            initialValue: String(
                configuration.discovery.responseWindowMilliseconds
            )
        )
        _discoveryAttemptCountText = State(
            initialValue: String(configuration.discovery.attemptCount)
        )
        _lights = State(
            initialValue: configuration.lights.map {
                LightDraft(configuration: $0)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            lightsSection
            monitorSection
            discoverySettingsSection
        }
        .padding(24)
        .frame(width: 700, height: 640)
        .navigationTitle("BetterBrightness")
        .defaultFocus($isDisplayIDFocused, false)
        .background {
            SettingsFocusMonitor {
                isDisplayIDFocused = false
                isResponseWindowFocused = false
                isAttemptCountFocused = false
            }
        }
        .alert("Unable to Save", isPresented: $showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert(
            "Remove Light?",
            isPresented: $showsDeleteConfirmation,
            presenting: lightPendingDeletion
        ) { light in
            Button("Remove", role: .destructive) {
                removeLight(light.id)
                lightPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                lightPendingDeletion = nil
            }
        } message: { light in
            Text(
                "\(light.displayName) at "
                    + "\(light.ip.isEmpty ? "this address" : light.ip) "
                    + "will be removed from BetterBrightness."
            )
        }
    }

    private var monitorSection: some View {
        GroupBox {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("BetterDisplay display ID")

                    Button {
                        showsMonitorHelp.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(monitorHelpText)
                    .popover(isPresented: $showsMonitorHelp, arrowEdge: .bottom) {
                        Text(monitorHelpText)
                            .font(.callout)
                            .padding(12)
                            .frame(width: 280, alignment: .leading)
                    }
                }

                Spacer()

                TextField("Display ID", text: displayIDBinding)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 72)
                    .focused($isDisplayIDFocused)
                    .onSubmit(saveDisplayIDIfNeeded)
                    .onChange(of: isDisplayIDFocused) { wasFocused, isFocused in
                        if wasFocused && !isFocused {
                            saveDisplayIDIfNeeded()
                        }
                    }
            }
            .padding(4)
        } label: {
            Text("Monitor")
                .font(.headline)
        }
    }

    private var lightsSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                discoveryControls

                Divider()

                List {
                    ForEach(sortedLightIDs, id: \.self) { lightID in
                        if let lightIndex = lights.firstIndex(where: {
                            $0.id == lightID
                        }) {
                            LightSettingsRow(
                                light: $lights[lightIndex],
                                canDelete: lights.count > 1,
                                onCommit: {
                                    saveConfiguration()
                                }
                            ) {
                                lightPendingDeletion = lights[lightIndex]
                                showsDeleteConfirmation = true
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.visible)

            }
            .padding(4)
        } label: {
            HStack {
                Text("WiZ Lights")
                    .font(.headline)

                Spacer()

                Text("\(lights.count) configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var sortedLightIDs: [UUID] {
        lights.sorted { firstLight, secondLight in
            if firstLight.isEnabled != secondLight.isEnabled {
                return firstLight.isEnabled
            }

            let nameComparison = firstLight.displayName.localizedStandardCompare(
                secondLight.displayName
            )
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return firstLight.id.uuidString < secondLight.id.uuidString
        }
        .map(\.id)
    }

    private var discoveryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    discoverLights()
                } label: {
                    Label(
                        "Discover Lights",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                }
                .disabled(isDiscovering)

                if isDiscovering {
                    ProgressView()
                        .controlSize(.small)
                    Text(
                        "Attempt \(discoveryAttempt) of "
                            + "\(discoveryTotalAttempts)"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    lights.append(LightDraft())
                } label: {
                    Label("Add Manually", systemImage: "plus")
                }
            }

            if let discoveryResultText {
                Text(discoveryResultText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var discoverySettingsSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("Response window")

                        Button {
                            showsResponseWindowHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(responseWindowHelpText)
                        .popover(
                            isPresented: $showsResponseWindowHelp,
                            arrowEdge: .bottom
                        ) {
                            Text(responseWindowHelpText)
                                .font(.callout)
                                .padding(12)
                                .frame(width: 320, alignment: .leading)
                        }
                    }

                    Spacer()

                    TextField(
                        "Milliseconds",
                        text: discoveryResponseWindowBinding
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 80)
                    .focused($isResponseWindowFocused)
                    .onSubmit(saveDiscoverySettingsIfNeeded)
                    .onChange(of: isResponseWindowFocused) {
                        wasFocused,
                        isFocused in
                        if wasFocused && !isFocused {
                            saveDiscoverySettingsIfNeeded()
                        }
                    }

                    Text("ms")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                }

                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("Attempts")

                        Button {
                            showsAttemptCountHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(attemptCountHelpText)
                        .popover(
                            isPresented: $showsAttemptCountHelp,
                            arrowEdge: .bottom
                        ) {
                            Text(attemptCountHelpText)
                                .font(.callout)
                                .padding(12)
                                .frame(width: 320, alignment: .leading)
                        }
                    }

                    Spacer()

                    TextField("Attempts", text: discoveryAttemptCountBinding)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 80)
                        .focused($isAttemptCountFocused)
                        .onSubmit(saveDiscoverySettingsIfNeeded)
                        .onChange(of: isAttemptCountFocused) {
                            wasFocused,
                            isFocused in
                            if wasFocused && !isFocused {
                                saveDiscoverySettingsIfNeeded()
                            }
                        }

                    Color.clear
                        .frame(width: 24, height: 1)
                }
            }
            .padding(4)
        } label: {
            Text("Discovery")
                .font(.headline)
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

    private func discoverLights() {
        guard saveConfiguration() else { return }

        let discoveryConfiguration = configurationStore.configuration.discovery
        isDiscovering = true
        discoveryAttempt = 0
        discoveryTotalAttempts = discoveryConfiguration.attemptCount
        discoveryResultText = nil

        WiZDiscoveryService.discover(
            configuration: discoveryConfiguration
        ) { attempt in
            discoveryAttempt = attempt
        } completion: { result in
            isDiscovering = false

            switch result {
            case .success(let discoveredLights):
                do {
                    let summary = try configurationStore.applyDiscoveryResults(
                        discoveredLights
                    )
                    mergeDiscoveryChangesIntoDrafts()
                    discoveryResultText = discoverySummaryText(summary)
                } catch {
                    errorMessage = error.localizedDescription
                    showsError = true
                }

            case .failure(let error):
                errorMessage = error.localizedDescription
                showsError = true
            }
        }
    }

    private func mergeDiscoveryChangesIntoDrafts() {
        for savedLight in configurationStore.configuration.lights {
            if let index = lights.firstIndex(where: { $0.id == savedLight.id }) {
                lights[index].macAddress = savedLight.macAddress
                lights[index].ip = savedLight.ip
                lights[index].isIPAddressVerified =
                    savedLight.isIPAddressVerified
                lights[index].deviceInfo = savedLight.deviceInfo
            } else {
                lights.append(LightDraft(configuration: savedLight))
            }
        }
    }

    private func discoverySummaryText(
        _ summary: DiscoveryMergeSummary
    ) -> String {
        guard summary.foundLights > 0 else {
            return "No WiZ lights were found."
        }

        var details = [
            "\(summary.foundLights) "
                + "\(summary.foundLights == 1 ? "light" : "lights") found"
        ]
        if summary.newLights > 0 {
            details.append("\(summary.newLights) new")
        }
        if summary.updatedIPs > 0 {
            details.append(
                "\(summary.updatedIPs) IP "
                    + "\(summary.updatedIPs == 1 ? "address" : "addresses") "
                    + "updated"
            )
        }
        if summary.identifiedExistingLights > 0 {
            details.append(
                "\(summary.identifiedExistingLights) existing "
                    + "\(summary.identifiedExistingLights == 1 ? "light" : "lights") "
                    + "identified"
            )
        }
        if summary.invalidatedIPs > 0 {
            details.append(
                "\(summary.invalidatedIPs) waiting for rediscovery"
            )
        }

        return details.joined(separator: " · ")
    }

    private func removeLight(_ id: UUID) {
        guard lights.count > 1 else { return }
        lights.removeAll { $0.id == id }
        saveConfiguration()
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

private struct LightSettingsRow: View {
    @Binding var light: LightDraft
    let canDelete: Bool
    let onCommit: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var showsBrightnessMappingHelp = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case ip
        case monitorMin
        case monitorMax
        case lightMin
        case lightMax
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Name") {
                    TextField("Light Name", text: $light.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)
                        .focused($focusedField, equals: .name)
                        .onSubmit(onCommit)
                }

                manualIPAddressField

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text("Brightness Mapping")
                            .font(.subheadline.weight(.semibold))

                        Button {
                            showsBrightnessMappingHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(brightnessMappingHelpText)
                        .popover(
                            isPresented: $showsBrightnessMappingHelp,
                            arrowEdge: .bottom
                        ) {
                            brightnessMappingHelp
                        }
                    }

                    percentageRow(
                        "Monitor minimum",
                        value: $light.monitorMin,
                        field: .monitorMin
                    )

                    percentageRow(
                        "Monitor maximum",
                        value: $light.monitorMax,
                        field: .monitorMax
                    )

                    Divider()

                    percentageRow(
                        "Light minimum",
                        value: $light.lightMinPercent,
                        field: .lightMin
                    )

                    percentageRow(
                        "Light maximum",
                        value: $light.lightMaxPercent,
                        field: .lightMax
                    )

                }
            }
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(light.displayName)
                        .lineLimit(1)

                    if !light.isIPAddressVerified {
                        Label(
                            "Waiting for rediscovery",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 16)

                Toggle("Send brightness commands", isOn: $light.isEnabled)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .fixedSize()
                    .help(
                        light.isIPAddressVerified
                            ? "When on, this light receives brightness updates from BetterBrightness."
                            : "No commands are sent until this light is rediscovered."
                    )
                    .onChange(of: light.isEnabled) {
                        onCommit()
                    }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!canDelete)
                .help("Remove light")
            }
        }
        .padding(.vertical, 8)
        .onChange(of: focusedField) { previousField, newField in
            if previousField != nil && previousField != newField {
                onCommit()
            }
        }
    }

    @ViewBuilder
    private var manualIPAddressField: some View {
        if light.macAddress == nil {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("IP Address") {
                    TextField("192.168.1.2", text: $light.ip)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)
                        .focused($focusedField, equals: .ip)
                        .onSubmit(onCommit)
                }

                Text("Run discovery to identify this light by MAC address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var brightnessMappingHelpText: String {
        "Choose how the monitor brightness range maps to the light "
            + "brightness range. Values between the limits scale "
            + "proportionally. "
            + brightnessMappingExample
    }

    private var brightnessMappingHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Brightness Mapping")
                .font(.headline)

            Text(
                "Choose how the monitor brightness range maps to the light "
                    + "brightness range. Values between the limits scale "
                    + "proportionally."
            )

            Text("Example")
                .font(.subheadline.weight(.semibold))

            Text(brightnessMappingExample)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(14)
        .frame(width: 360, alignment: .leading)
    }

    private var brightnessMappingExample: String {
        "With the monitor set to \(light.monitorMin)%–\(light.monitorMax)% "
            + "and the light set to "
            + "\(light.lightMinPercent)%–\(light.lightMaxPercent)%, monitor "
            + "brightness at \(light.monitorMin)% sets the light to "
            + "\(light.lightMinPercent)%, \(monitorMidpoint)% sets it to "
            + "\(lightMidpoint)%, and \(light.monitorMax)% sets it to "
            + "\(light.lightMaxPercent)%. Values outside the monitor range "
            + "stay at the nearest light limit."
    }

    private var monitorMidpoint: String {
        midpoint(between: light.monitorMin, and: light.monitorMax)
    }

    private var lightMidpoint: String {
        midpoint(
            between: light.lightMinPercent,
            and: light.lightMaxPercent
        )
    }

    private func midpoint(between minimum: Int, and maximum: Int) -> String {
        let sum = minimum + maximum
        return sum.isMultiple(of: 2) ? "\(sum / 2)" : "\(sum / 2).5"
    }

    private func percentageRow(
        _ title: String,
        value: Binding<Int>,
        field: Field
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 56)
                    .focused($focusedField, equals: field)
                    .onSubmit(onCommit)

                Text("%")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
