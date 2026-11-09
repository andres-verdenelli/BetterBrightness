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
    @State private var isDraggingLight = false
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
            List(selection: selectionBinding) {
                ForEach(rootIDs, id: \.self) { id in
                    if let group = groups.first(where: { $0.id == id }) {
                        DisclosureGroup(isExpanded: expansionBinding(group.id)) {
                            ForEach(memberIDs(group), id: \.self) { id in lightRow(id) }
                        } label: {
                            Label {
                                HStack {
                                    Text(group.name).lineLimit(1)
                                    Spacer()
                                    Text("\(group.memberIDs.count)").foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "folder") }
                        }
                        .tag(group.id)
                        .dropDestination(for: String.self) { items, _ in
                            isDraggingLight = false
                            return acceptDrop(items, destination: group.id)
                        }
                    } else {
                        lightRow(id)
                    }
                }
                if isDraggingLight {
                    Label("Make independent", systemImage: "arrow.uturn.backward")
                        .font(.caption).foregroundStyle(.secondary)
                        .dropDestination(for: String.self) { items, _ in
                            isDraggingLight = false
                            return acceptDrop(items, destination: nil)
                        }
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: UUID.self) { ids in
                sidebarContextMenu(ids)
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first { beginRename(id) }
            }
        } detail: {
            if let id = selectedLightID,
               let index = groups.firstIndex(where: { $0.id == id }) {
                GroupDetailView(group: $groups[index],
                                members: lights.filter { groups[index].memberIDs.contains($0.id) },
                                onCommit: { saveConfiguration() },
                                onSelect: { selectItem($0) },
                                onUngroup: { groupPendingUngroup = groups[index] })
                    .id(id)
            } else if let id = selectedLightID,
                      let index = lights.firstIndex(where: { $0.id == id && !$0.isHidden }) {
                LightDetailView(
                    light: $lights[index],
                    group: groups.first { $0.memberIDs.contains(id) },
                    onSelectGroup: { selectItem($0) },
                    onLeaveGroup: { runAction { try configurationStore.moveLights([id], to: nil) } },
                    onHide: { runAction { try configurationStore.setLightHidden(id, hidden: true) } },
                    onRemove: { requestRemoval(lights[index]) },
                    isRenaming: renamingLightID == id,
                    renameText: $renameText,
                    onBeginRename: { beginRename(id) },
                    onFinishRename: finishRename,
                    onCancelRename: cancelRename,
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
        .alert("Remove Light?", isPresented: $showsDeleteConfirmation,
               presenting: lightPendingDeletion) { light in
            Button("Remove", role: .destructive) { removeLight(light.id) }
            Button("Cancel", role: .cancel) {}
        } message: { light in
            Text("\(light.displayName) will be removed from BetterBrightness.")
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

    private var rootIDs: [UUID] {
        let entries = groups.map { ($0.id, $0.name) } + lights.filter { light in
            !light.isHidden && !groups.contains { $0.memberIDs.contains(light.id) }
        }.map { ($0.id, $0.displayName) }
        return entries.sorted {
            let order = $0.1.localizedStandardCompare($1.1)
            return order == .orderedSame ? $0.0.uuidString < $1.0.uuidString : order == .orderedAscending
        }.map { $0.0 }
    }

    private var sortedGroups: [LightGroup] {
        groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var independentLightIDs: [UUID] {
        sortedLightIDs.filter { id in !groups.contains { $0.memberIDs.contains(id) } }
    }

    private func memberIDs(_ group: LightGroup) -> [UUID] {
        lights.filter { !$0.isHidden && group.memberIDs.contains($0.id) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }.map(\.id)
    }

    private func expansionBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { expandedGroups.contains(id) }, set: {
            if $0 { expandedGroups.insert(id) } else { expandedGroups.remove(id) }
        })
    }

    @ViewBuilder private func lightRow(_ id: UUID) -> some View {
        if let light = lights.first(where: { $0.id == id }) {
            sidebarRow(light)
                .tag(id)
                .itemProvider {
                    isDraggingLight = true
                    let ids = selectedIDs.contains(id) ? selectedLightIDs : [id]
                    let provider = SidebarDragProvider(object: ids.map(\.uuidString).sorted().joined(separator: ",") as NSString)
                    provider.onEnd = { Task { @MainActor in isDraggingLight = false } }
                    return provider
                }

        }
    }

    @ViewBuilder private func sidebarContextMenu(_ ids: Set<UUID>) -> some View {
        if ids.count == 1, let id = ids.first, let group = groups.first(where: { $0.id == id }) {
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
                if !groups.isEmpty {
                    Menu("Move to Group") {
                        ForEach(sortedGroups) { group in
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
                    Button("Hide Light") {
                        runAction { try configurationStore.setLightHidden(light.id, hidden: true) }
                    }
                    Button("Remove Light…", role: .destructive) { requestRemoval(light) }
                }
            }
        }
    }

    private var selectedLightIDs: Set<UUID> {
        Set(lights.filter { !$0.isHidden && selectedIDs.contains($0.id) }.map(\.id))
    }

    private func acceptDrop(_ items: [String], destination: UUID?) -> Bool {
        let components = items.flatMap { $0.split(separator: ",").map(String.init) }
        let ids = Set(components.compactMap(UUID.init(uuidString:)))
        guard components.count == ids.count, !ids.isEmpty,
              ids.allSatisfy({ id in lights.contains { $0.id == id && !$0.isHidden } }) else { return false }
        let succeeded = runAction { try configurationStore.moveLights(ids, to: destination) }
        if succeeded, let destination { expandedGroups.insert(destination) }
        return succeeded
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
              let light = lights.first(where: { $0.id == id }) else { return }
        finishRename()
        if selectedLightID != id {
            guard saveConfiguration() else { return }
            selectedIDs = [id]
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
        cancelRename()
        lightPendingDeletion = light
        showsDeleteConfirmation = true
    }

    private func removeLight(_ id: UUID) {
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
    let onSelectGroup: (UUID) -> Void
    let onLeaveGroup: () -> Void
    let onHide: () -> Void
    let onRemove: () -> Void
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
            if let group {
                Section {
                    Button("Brightness controlled by \(group.name)") { onSelectGroup(group.id) }
                    Button("Remove from Group", action: onLeaveGroup)
                }
            } else {
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
                    nameEditor.multilineTextAlignment(.trailing)
                }
                LabeledContent("IP address", value: light.ip)
                if let mac = light.macAddress {
                    LabeledContent("MAC address", value: WiZMACAddress.display(mac))
                }
            }
            Section("Actions") {
                Button("Hide Light", action: onHide)
                Button("Remove Light…", role: .destructive, action: onRemove)
                Text("Hidden lights can be restored in Advanced Settings with Sync off.")
                    .font(.caption).foregroundStyle(.secondary)
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

private struct GroupDetailView: View {
    @Binding var group: LightGroup
    let members: [LightDraft]
    let onCommit: () -> Void
    let onSelect: (UUID) -> Void
    let onUngroup: () -> Void
    @FocusState private var nameFocused: Bool

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
            Section("Group") {
                TextField("Group name", text: $group.name).focused($nameFocused).onSubmit(onCommit)
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
            Section("Members") {
                ForEach(members.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }) { light in
                    Button { onSelect(light.id) } label: {
                        HStack {
                            Label(light.displayName, systemImage: "lightbulb")
                            Spacer()
                            Text(light.isIPAddressVerified ? light.ip : "Waiting for rediscovery")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                Button("Ungroup…", role: .destructive, action: onUngroup)
            }
        }
        .formStyle(.grouped)
        .onChange(of: nameFocused) { was, now in if was && !now { onCommit() } }
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

private final class SidebarDragProvider: NSItemProvider, @unchecked Sendable {
    var onEnd: (@Sendable () -> Void)?
    deinit { onEnd?() }
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
