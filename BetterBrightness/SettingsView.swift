import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.isGroupPreview) private var isGroupPreview
    @ObservedObject var configurationStore: ConfigurationStore
    @ObservedObject var discovery: DiscoveryController
    @ObservedObject var launchAtLogin: LaunchAtLoginController

    @State private var displayIDText: String
    @State private var discoveryResponseWindowText: String
    @State private var discoveryAttemptCountText: String
    @State private var lights: [LightDraft]
    @State private var selectedIDs: Set<UUID> = []
    @State private var groups: [LightGroup]
    @State private var expandedGroups: Set<UUID> = []
    @State private var showsCreateGroup = false
    @State private var groupName = ""
    @State private var groupSourceID: UUID?
    @State private var groupMemberIDs: Set<UUID> = []
    @State private var groupPendingUngroup: LightGroup?
    private var selectedLightID: UUID? { selectedIDs.count == 1 ? selectedIDs.first : nil }
    @State private var isSidebarVisible = true
    @State private var showsAdvanced = false
    @State private var errorMessage = ""
    @State private var showsError = false
    @State private var lightPendingDeletion: LightDraft?
    @State private var showsDeleteConfirmation = false
    @State private var renamingLightID: UUID?
    @State private var renameText = ""
    @FocusState private var sidebarRenameFocus: UUID?
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
        _groups = State(initialValue: configuration.groups)
        _expandedGroups = State(initialValue: Set(configuration.groups.map(\.id)))
        _selectedIDs = State(initialValue: Set(configuration.lights.first(where: { !$0.isHidden }).map { [$0.id] } ?? []))
    }

    var body: some View {
        SettingsSplitView(isSidebarVisible: $isSidebarVisible) {
            sidebar
        } detail: {
            detail
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle(groups.first(where: { $0.id == selectedLightID })?.name ?? lights.first(where: { $0.id == selectedLightID })?.displayName ?? "Settings")
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
        .sheet(isPresented: $showsCreateGroup) { createGroupSheet }
        .confirmationDialog("Ungroup Lights?", isPresented: Binding(
            get: { groupPendingUngroup != nil },
            set: { if !$0 { groupPendingUngroup = nil } }
        ), presenting: groupPendingUngroup) { group in
            Button("Ungroup", role: .destructive) {
                runAction { try configurationStore.ungroup(group.id) }
                groupPendingUngroup = nil
            }
        } message: { group in
            Text("The lights in \(group.name) will keep its brightness settings with Sync on.")
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
        .alert("Delete Light?", isPresented: $showsDeleteConfirmation,
               presenting: lightPendingDeletion) { light in
            Button("Delete", role: .destructive) { removeLight(light.id) }
            Button("Cancel", role: .cancel) {}
        } message: { light in
            Text("\(light.displayName) will be deleted from BetterBrightness.")
        }
    }

    private var sidebar: some View {
        OrderedSidebar(
            roots: rootIDs,
            children: Dictionary(uniqueKeysWithValues: groups.map { ($0.id, memberIDs($0)) }),
            selected: selectedIDs, expanded: expandedGroups,
            content: { id in
                AnyView(sidebarContent(id).contextMenu {
                    sidebarContextMenu(selectedIDs.contains(id) ? selectedIDs : [id])
                })
            },
            onSelect: { selectionBinding.wrappedValue = $0 },
            onExpand: { expandedGroups = $0 },
            prepareDrag: { finishRename(); return saveConfiguration() },
            onMove: { ids, parent, index in
                do {
                    try configurationStore.reorderSidebar(ids, parent: parent, index: index)
                    reloadSnapshot()
                    return true
                } catch {
                    errorMessage = error.localizedDescription
                    showsError = true
                    return false
                }
            }
        )
    }

    @ViewBuilder private func sidebarContent(_ id: UUID) -> some View {
        if let group = groups.first(where: { $0.id == id }) {
            groupRow(group)
                .font(.system(size: 13))
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if let light = lights.first(where: { $0.id == id }) {
            sidebarRow(light)
                .font(.system(size: 13))
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func groupRow(_ group: LightGroup) -> some View {
        HStack {
            groupLabel(group)
            Button {
                expansionBinding(group.id).wrappedValue.toggle()
            } label: {
                Image(systemName: expandedGroups.contains(group.id) ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 36, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle \(group.name)")
        }
        .foregroundStyle(selectedIDs.contains(group.id) ? Color.white : Color.primary)
        .tag(group.id)
    }

    private func groupLabel(_ group: LightGroup) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .frame(width: 20)
            if renamingLightID == group.id {
                TextField("Group name", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused($sidebarRenameFocus, equals: group.id)
                    .onSubmit(finishRename)
                    .onExitCommand(perform: cancelRename)
                    .onAppear { sidebarRenameFocus = group.id }
                    .onChange(of: sidebarRenameFocus) { old, new in
                        if old == group.id && new != group.id { finishRename() }
                    }
            } else {
                Text(group.name).lineLimit(1)
            }
            Spacer()
            Text("\(group.memberIDs.count)")
                .foregroundStyle(selectedIDs.contains(group.id) ? Color.white.opacity(0.8) : Color.secondary)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder private var detail: some View {
        if let id = selectedLightID,
           let index = groups.firstIndex(where: { $0.id == id }) {
            GroupDetailView(group: $groups[index],
                            onCommit: { saveConfiguration() })
                .id(id)
        } else if let id = selectedLightID,
                  let index = lights.firstIndex(where: { $0.id == id && !$0.isHidden }) {
            LightDetailView(
                light: $lights[index],
                group: groups.first { $0.memberIDs.contains(id) },
                onCommit: {
                    guard selectedLightID == id else { return }
                    saveConfiguration()
                }
            )
            .id(id)
        } else {
            ContentUnavailableView(selectedIDs.count > 1 ? "\(selectedIDs.count) Items Selected" : "Select a Light or Group",
                                   systemImage: "folder")
        }
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(get: { selectedIDs }, set: { ids in
            finishRename()
            guard ids != selectedIDs, saveConfiguration() else { return }
            selectedIDs = ids
        })
    }

    private func selectItem(_ id: UUID) {
        finishRename()
        guard saveConfiguration() else { return }
        selectedIDs = [id]
    }

    private var rootIDs: [UUID] { configurationStore.configuration.sidebarOrder }

    private var sortedGroups: [LightGroup] {
        groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var independentLightIDs: [UUID] {
        sortedLightIDs.filter { id in !groups.contains { $0.memberIDs.contains(id) } }
    }

    private func memberIDs(_ group: LightGroup) -> [UUID] {
        group.memberIDs.filter { id in lights.contains { $0.id == id && !$0.isHidden } }
    }

    private func expansionBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { expandedGroups.contains(id) }, set: {
            if $0 { expandedGroups.insert(id) } else { expandedGroups.remove(id) }
        })
    }

    @ViewBuilder private func sidebarContextMenu(_ ids: Set<UUID>) -> some View {
        if ids.count == 1, let id = ids.first, let group = groups.first(where: { $0.id == id }) {
            Button("Rename") { beginRename(group.id) }
            Button("Ungroup…", role: .destructive) { groupPendingUngroup = group }
        } else {
            let selectedLights = lights.filter { !$0.isHidden && ids.contains($0.id) }
            let lightIDs = Set(selectedLights.map(\.id))
            if !lightIDs.isEmpty && lightIDs.count == ids.count {
                if lightIDs.count >= 2 && lightIDs.allSatisfy({ id in
                    !groups.contains { $0.memberIDs.contains(id) }
                }) {
                    Button("Group Lights…") { beginGroup(lightIDs) }
                }
                let destinations = sortedGroups.filter { !lightIDs.isSubset(of: $0.memberIDs) }
                if !destinations.isEmpty {
                    Menu("Move to Group") {
                        ForEach(destinations) { group in
                            Button(group.name) {
                                if runAction({ try configurationStore.moveLights(lightIDs, to: group.id) }) {
                                    expandedGroups.insert(group.id)
                                }
                            }
                        }
                    }
                }
                if lightIDs.contains(where: { id in groups.contains { $0.memberIDs.contains(id) } }) {
                    Button("Remove from Group") {
                        runAction { try configurationStore.moveLights(lightIDs, to: nil) }
                    }
                }
                if let light = selectedLights.first, lightIDs.count == 1 {
                    Divider()
                    Button("Rename") { beginRename(light.id) }
                    if !groups.contains(where: { $0.memberIDs.contains(light.id) }) {
                    Button("Hide Light") {
                        runAction { try configurationStore.setLightHidden(light.id, hidden: true) }
                    }
                        Button("Delete Light…", role: .destructive) { requestRemoval(light) }
                    }
                }
            }
        }
    }

    private var selectedLightIDs: Set<UUID> {
        Set(lights.filter { !$0.isHidden && selectedIDs.contains($0.id) }.map(\.id))
    }

    private func beginGroup(_ ids: Set<UUID>) {
        guard saveConfiguration() else { return }
        groupMemberIDs = ids
        groupSourceID = lights.filter { ids.contains($0.id) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }.first?.id
        groupName = ""
        showsCreateGroup = true
    }

    private var validGroupName: Bool {
        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !groups.contains { $0.name.lowercased() == name.lowercased() }
    }

    private var createGroupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Group Lights").font(.title2)
            TextField("Group name", text: $groupName)
            Text("Lights").font(.headline)
            ForEach(lights.filter { groupMemberIDs.contains($0.id) }.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }) { light in Label(light.displayName, systemImage: "lightbulb") }
            Picker("Use settings from", selection: $groupSourceID) {
                ForEach(lights.filter { groupMemberIDs.contains($0.id) }.sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }) { light in Text(light.displayName).tag(Optional(light.id)) }
            }
            Text("The selected light supplies brightness settings and Sync for every member.")
                .font(.caption).foregroundStyle(.secondary)
            if !groupName.isEmpty && !validGroupName {
                Text("Use a nonempty name that differs from other groups.").foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { showsCreateGroup = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create Group") {
                    guard let source = groupSourceID else { return }
                    if runAction({
                        let id = try configurationStore.createGroup(name: groupName, memberIDs: groupMemberIDs, sourceID: source)
                        selectedIDs = [id]
                        expandedGroups.insert(id)
                    }) { showsCreateGroup = false }
                }
                .disabled(!validGroupName || groupSourceID == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 430)
        .alert("Unable to Save", isPresented: $showsError) { Button("OK", role: .cancel) {} }
            message: { Text(errorMessage) }
    }

    /// Flush edits first; store actions publish a complete snapshot only after a successful save.
    @discardableResult private func runAction(_ action: () throws -> Void) -> Bool {
        finishRename()
        guard saveConfiguration() else { return false }
        do {
            try action()
            reloadSnapshot()
            return true
        } catch {
            errorMessage = error.localizedDescription
            showsError = true
            return false
        }
    }

    private func reloadSnapshot() {
        let configuration = configurationStore.configuration
        lights = configuration.lights.map(LightDraft.init(configuration:))
        groups = configuration.groups
        selectedIDs = selectedIDs.intersection(Set(lights.filter { !$0.isHidden }.map(\.id) + groups.map(\.id)))
    }

    private func sidebarRow(_ light: LightDraft) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: light.isIPAddressVerified ? "lightbulb" : "exclamationmark.triangle")
                .foregroundStyle(selectedIDs.contains(light.id) ? Color.white : (light.isIPAddressVerified ? Color.secondary : Color.orange))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                if renamingLightID == light.id {
                    TextField("Light name", text: $renameText)
                        .textFieldStyle(.plain)
                        .focused($sidebarRenameFocus, equals: light.id)
                        .onSubmit(finishRename)
                        .onExitCommand(perform: cancelRename)
                        .onAppear { sidebarRenameFocus = light.id }
                        .onChange(of: sidebarRenameFocus) { old, new in
                            if old == light.id && new != light.id { finishRename() }
                        }
                } else {
                    Text(light.displayName)
                        .foregroundStyle(selectedIDs.contains(light.id) ? Color.white : Color.primary)
                        .lineLimit(1)
                        .help(light.displayName)
                }
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
        .contentShape(Rectangle())
    }

    private var sortedLightIDs: [UUID] {
        lights.filter { !$0.isHidden }.sorted { first, second in
            if first.isEnabled != second.isEnabled { return first.isEnabled }
            let comparison = first.displayName.localizedStandardCompare(second.displayName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return first.id.uuidString < second.id.uuidString
        }.map(\.id)
    }

    private func beginRename(_ id: UUID) {
        guard renamingLightID != id,
              let name = lights.first(where: { $0.id == id })?.name ?? groups.first(where: { $0.id == id })?.name else { return }
        finishRename()
        if selectedLightID != id {
            guard saveConfiguration() else { return }
            selectedIDs = [id]
        }
        renameText = name
        renamingLightID = id
    }

    private func finishRename() {
        if let id = renamingLightID, var group = groups.first(where: { $0.id == id }) {
            group.name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
            renamingLightID = nil
            runAction { try configurationStore.updateGroup(group) }
            return
        }
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
                    if isGroupPreview {
                        Text("Simulated preview · device control and Launch at Login are disabled.")
                    } else {
                        LaunchAtLoginControl(controller: launchAtLogin)
                    }
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
                Section("Hidden Lights") {
                    let hidden = lights.filter(\.isHidden)
                    if hidden.isEmpty { Text("No hidden lights").foregroundStyle(.secondary) }
                    ForEach(hidden) { light in
                        LabeledContent(light.displayName) {
                            Button("Show Light") {
                                runAction { try configurationStore.setLightHidden(light.id, hidden: false) }
                            }
                        }
                    }
                    Text("Restored lights are independent with Sync off.")
                        .font(.caption).foregroundStyle(.secondary)
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
                discovery: discoveryConfiguration,
                groups: groups
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
        guard !groups.contains(where: { $0.memberIDs.contains(light.id) }) else { return }
        cancelRename()
        lightPendingDeletion = light
        showsDeleteConfirmation = true
    }

    private func removeLight(_ id: UUID) {
        guard !configurationStore.configuration.groups.contains(where: { $0.memberIDs.contains(id) }) else { return }
        if !configurationStore.configuration.lights.contains(where: { $0.id == id }) {
            lights.removeAll { $0.id == id }
            selectedIDs.remove(id)
            lightPendingDeletion = nil
            return
        }
        if runAction({ try configurationStore.removeLight(id) }) {
            if selectedIDs.isEmpty, let first = sortedLightIDs.first { selectedIDs = [first] }
            lightPendingDeletion = nil
        }
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
    let group: LightGroup?
    let onCommit: () -> Void

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
            if group == nil {
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

            }

            Section("Light") {
                LabeledContent("Name") {
                    Text(light.displayName).multilineTextAlignment(.trailing)
                }
                LabeledContent("IP address", value: light.ip)
                if let mac = light.macAddress {
                    LabeledContent("MAC address", value: WiZMACAddress.display(mac))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(light.displayName)
    }
}


private struct GroupDetailView: View {
    @Binding var group: LightGroup
    let onCommit: () -> Void

    private func value(_ keyPath: KeyPath<BrightnessMapping, Double>) -> Binding<Int> {
        Binding(get: { Int(group.mapping[keyPath: keyPath].rounded()) }, set: { value in
            let m = group.mapping
            group.mapping = BrightnessMapping(
                monitorMin: keyPath == \.monitorMin ? Double(value) : m.monitorMin,
                monitorMax: keyPath == \.monitorMax ? Double(value) : m.monitorMax,
                lightMinPercent: keyPath == \.lightMinPercent ? Double(value) : m.lightMinPercent,
                lightMaxPercent: keyPath == \.lightMaxPercent ? Double(value) : m.lightMaxPercent)
        })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Sync brightness", isOn: $group.isEnabled)
                    .toggleStyle(.switch).onChange(of: group.isEnabled) { onCommit() }
            }
            Section {
                FollowBrightnessEditor(
                    monitorMin: value(\.monitorMin), monitorMax: value(\.monitorMax),
                    lightMin: value(\.lightMinPercent), lightMax: value(\.lightMaxPercent),
                    onCommit: onCommit
                )
            } header: { Text("Follow monitor brightness") }
              footer: { Text("These settings control every member. Offline lights do not stop the others from syncing.") }
        }
        .formStyle(.grouped)
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
