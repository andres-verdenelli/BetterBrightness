import Combine
import Foundation

enum LightGroupTests {
    @MainActor static func run() throws {
        try ordering()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let suite = "BetterBrightness.GroupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ConfigurationStore(defaults: defaults)
        let dim = BrightnessMapping(monitorMin: 20, monitorMax: 70, lightMinPercent: 5, lightMaxPercent: 60)
        let bright = BrightnessMapping(monitorMin: 40, monitorMax: 90, lightMinPercent: 30, lightMaxPercent: 100)
        let a = LightConfiguration(name: "A", macAddress: "020000000001", ip: "192.0.2.1", isEnabled: false, mapping: dim)
        let b = LightConfiguration(name: "B", macAddress: "020000000002", ip: "192.0.2.2", isEnabled: true, mapping: bright)
        let c = LightConfiguration(name: "C", macAddress: "020000000003", ip: "192.0.2.3", isEnabled: true, mapping: bright)
        let d = LightConfiguration(name: "D", macAddress: "020000000004", ip: "192.0.2.4", isEnabled: false, mapping: dim)
        try store.save(displayID: 3, lights: [a, b, c, d])
        let g = try store.createGroup(name: "  Office  ", memberIDs: [a.id, b.id], sourceID: a.id)
        precondition(store.configuration.groups[0].name == "Office")
        precondition(store.configuration.groups[0].mapping == dim && !store.configuration.groups[0].isEnabled)
        precondition(store.configuration.effectiveLights[1].mapping == dim && !store.configuration.effectiveLights[1].isEnabled)
        precondition(store.configuration.lights[1].mapping == bright, "Group is the effective source; do not overwrite stored independent settings on entry")
        let restored = ConfigurationStore(defaults: defaults)
        precondition(restored.configuration.group(containing: b.id)?.id == g)
        precondition(restored.configuration.effectiveLights[1].mapping == dim)
        print("PASS: group creation uses chosen source, trims name, persists membership and shared Sync/mapping")

        func rejects(_ action: () throws -> Void) {
            let before = try! encoder.encode(store.configuration)
            do { try action(); preconditionFailure("Expected validation error") } catch {}
            precondition(try! encoder.encode(store.configuration) == before)
        }
        rejects { _ = try store.createGroup(name: " office ", memberIDs: [c.id, d.id], sourceID: c.id) }
        rejects { _ = try store.createGroup(name: " \n ", memberIDs: [c.id, d.id], sourceID: c.id) }
        rejects { _ = try store.createGroup(name: "Mixed", memberIDs: [b.id, c.id], sourceID: b.id) }
        rejects { _ = try store.createGroup(name: "One", memberIDs: [c.id], sourceID: c.id) }
        rejects { _ = try store.createGroup(name: "Bad source", memberIDs: [c.id, d.id], sourceID: a.id) }
        print("PASS: invalid names, grouped creation, single-member creation and invalid source are rejected atomically")

        var group = store.configuration.groups[0]
        group.mapping = bright
        group.isEnabled = true
        try store.updateGroup(group)
        precondition(store.configuration.effectiveLights[0].mapping == bright)
        precondition(store.configuration.effectiveLights[0].isEnabled)
        let h = try store.createGroup(name: "Other", memberIDs: [c.id, d.id], sourceID: d.id)
        try store.moveLights([a.id], to: h)
        precondition(store.configuration.groups.first { $0.id == g }?.memberIDs == [b.id])
        precondition(store.configuration.group(containing: a.id)?.id == h)
        precondition(store.configuration.effectiveLights[0].mapping == dim && !store.configuration.effectiveLights[0].isEnabled)
        try store.moveLights([b.id], to: h)
        precondition(store.configuration.groups.count == 1, "Moving the last member removes its old group")
        try store.moveLights([a.id], to: nil)
        precondition(store.configuration.group(containing: a.id) == nil)
        precondition(store.configuration.lights[0].mapping == dim && store.configuration.lights[0].isEnabled)
        // A mixed selection may move to an existing group.
        try store.moveLights([a.id, c.id], to: h)
        precondition(Set(store.configuration.groups[0].memberIDs) == Set([a.id, b.id, c.id, d.id]))
        print("PASS: shared edits, moves, one-member retention, empty removal, exit and mixed-selection moves")

        _ = try store.applyDiscoveryResults([
            DiscoveredWiZLight(macAddress: a.macAddress!, ipAddress: "192.0.2.101", deviceInfo: WiZDeviceInfo())
        ])
        precondition(store.configuration.lights[0].id == a.id && store.configuration.lights[0].ip == "192.0.2.101")
        precondition(store.configuration.group(containing: a.id)?.id == h)
        precondition(store.configuration.effectiveLights[0].mapping == dim)
        try store.setLightHidden(a.id, hidden: true)
        precondition(store.configuration.group(containing: a.id) == nil)
        precondition(store.configuration.lights[0].isHidden && !store.configuration.lights[0].isEnabled)
        precondition(store.configuration.lights[0].mapping == dim)
        rejects { _ = try store.createGroup(name: "Hidden", memberIDs: [a.id, b.id], sourceID: a.id) }
        rejects { try store.moveLights([a.id], to: h) }
        _ = try store.applyDiscoveryResults([
            DiscoveredWiZLight(macAddress: a.macAddress!, ipAddress: "192.0.2.102", deviceInfo: WiZDeviceInfo())
        ])
        precondition(store.configuration.lights[0].isHidden)
        try store.setLightHidden(a.id, hidden: false)
        precondition(!store.configuration.lights[0].isHidden && !store.configuration.lights[0].isEnabled)
        precondition(store.configuration.group(containing: a.id) == nil)
        try store.ungroup(h)
        precondition(store.configuration.groups.isEmpty)
        precondition(store.configuration.lights.dropFirst().allSatisfy { $0.mapping == dim && $0.isEnabled })
        print("PASS: discovery preserves UUID/group/settings, hide detaches, restore stays independent/off, ungroup copies mapping and enables Sync")

        let last = try store.createGroup(name: "Last", memberIDs: [a.id, b.id], sourceID: b.id)
        try store.removeLight(a.id)
        precondition(store.configuration.groups.first { $0.id == last }?.memberIDs == [b.id])
        try store.removeLight(b.id)
        precondition(store.configuration.groups.isEmpty)
        try store.removeLight(c.id)
        try store.removeLight(d.id)
        precondition(store.configuration.lights.isEmpty && store.configuration.groups.isEmpty)
        print("PASS: deletion removes references and empty groups, including the final light")

        // A legacy snapshot omits both new fields entirely.
        var object = try JSONSerialization.jsonObject(with: encoder.encode(AppConfiguration(monitor: .init(displayID: 3), lights: [a, b]))) as! [String: Any]
        object.removeValue(forKey: "groups")
        var legacyLights = object["lights"] as! [[String: Any]]
        for index in legacyLights.indices { legacyLights[index].removeValue(forKey: "isHidden") }
        object["lights"] = legacyLights
        let legacy = try JSONDecoder().decode(AppConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
        precondition(legacy.groups.isEmpty && legacy.lights.allSatisfy { !$0.isHidden })
        print("PASS: legacy configuration without groups or hidden flags remains compatible")

        // The same controller send loop runs with an injected transport, never real UDP.
        var unavailable = b
        unavailable.isIPAddressVerified = false
        var hidden = d
        hidden.isHidden = true
        let sendingGroup = LightGroup(name: "Sending", memberIDs: [a.id, b.id, c.id], isEnabled: true, mapping: bright)
        try store.save(displayID: 3, lights: [a, unavailable, c, hidden], groups: [sendingGroup])
        var sent: [(UUID, Int)] = []
        let controller = BrightnessController(configurationStore: store, startsServices: false) { value, light in
            sent.append((light.id, value))
        }
        controller.sendBrightnessToEnabledLights(60)
        precondition(sent.count == 2 && Set(sent.map { $0.0 }) == Set([a.id, c.id]))
        precondition(sent.allSatisfy { $0.1 == bright.dimmingValue(for: 60) })
        controller.pause()
        controller.sendBrightnessToEnabledLights(80)
        precondition(sent.count == 2)
        group = sendingGroup
        group.isEnabled = false
        try store.updateGroup(group)
        controller.resume()
        controller.sendBrightnessToEnabledLights(80)
        precondition(sent.count == 2)
        print("PASS: production send loop sends once per available member with group mapping; offline, hidden, paused and disabled members send nothing")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BetterBrightness.AtomicTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Configuration.json")
        let diskStore = ConfigurationStore(defaults: defaults, fileURL: file)
        precondition(diskStore.configuration.groups.count == 1, "Migrate legacy defaults when no file exists")
        try diskStore.moveLights([a.id], to: nil)
        let diskSnapshot = try Data(contentsOf: file)
        let diskReload = ConfigurationStore(defaults: defaults, fileURL: file)
        precondition(diskReload.configuration.group(containing: a.id) == nil, "Atomic file takes precedence over old defaults")
        do { _ = try diskReload.createGroup(name: " ", memberIDs: [a.id, c.id], sourceID: a.id); preconditionFailure() } catch {}
        precondition(try! Data(contentsOf: file) == diskSnapshot)
        // An existing directory cannot be replaced by an atomic data file.
        let badFile = directory.appendingPathComponent("existing-directory")
        try FileManager.default.createDirectory(at: badFile, withIntermediateDirectories: true)
        let diskFailure = ConfigurationStore(defaults: defaults, fileURL: badFile)
        let diskFailureBefore = try encoder.encode(diskFailure.configuration)
        do { try diskFailure.moveLights([a.id], to: nil); preconditionFailure() } catch {}
        precondition(try! encoder.encode(diskFailure.configuration) == diskFailureBefore)
        print("PASS: atomic file migration/reload and real filesystem write errors preserve the previous configuration")

        // Fail the commit after validation; neither published nor stored snapshots may change.
        var shouldFail = false
        let failing = ConfigurationStore(defaults: defaults) { data in
            if shouldFail { throw ConfigurationError.storageFailure }
            defaults.set(data, forKey: "betterBrightness.configuration")
        }
        var publications = 0
        let subscription = failing.$configuration.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        let before = try encoder.encode(failing.configuration)
        let persistedBefore = defaults.data(forKey: "betterBrightness.configuration")
        shouldFail = true
        let attempts: [() throws -> Void] = [
            { try failing.moveLights([a.id], to: nil) },
            { try failing.setLightHidden(c.id, hidden: true) },
            { try failing.ungroup(sendingGroup.id) },
            { try failing.removeLight(c.id) },
            { var edited = sendingGroup; edited.name = "Renamed"; try failing.updateGroup(edited) },
            { _ = try failing.applyDiscoveryResults([DiscoveredWiZLight(macAddress: a.macAddress!, ipAddress: "192.0.2.200", deviceInfo: WiZDeviceInfo())]) }
        ]
        for action in attempts {
            do { try action(); preconditionFailure("Expected storage failure") } catch {}
            precondition(try! encoder.encode(failing.configuration) == before)
            precondition(defaults.data(forKey: "betterBrightness.configuration") == persistedBefore)
        }
        precondition(publications == 0)
        shouldFail = false
        try failing.ungroup(sendingGroup.id)
        shouldFail = true
        let independentBefore = try encoder.encode(failing.configuration)
        do { _ = try failing.createGroup(name: "Failed", memberIDs: [a.id, c.id], sourceID: a.id); preconditionFailure() } catch {}
        precondition(try! encoder.encode(failing.configuration) == independentBefore)
        print("PASS: injected storage failures roll back membership/settings/identity and publish no partial state")
    }
    @MainActor private static func ordering() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let suite = "BetterBrightness.OrderTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let mapping = BrightnessMapping(monitorMin: 20, monitorMax: 90, lightMinPercent: 1, lightMaxPercent: 100)
        let lights = ["Delta", "Bravo", "Alpha", "Charlie", "Echo"].enumerated().map { index, name in
            LightConfiguration(name: name, ip: "192.0.2.\(index + 1)", isEnabled: false, mapping: mapping)
        }
        let store = ConfigurationStore(defaults: defaults)
        try store.save(displayID: 3, lights: lights)
        let initial = [lights[2].id, lights[1].id, lights[3].id, lights[0].id, lights[4].id]
        precondition(store.configuration.sidebarOrder == initial)
        try store.reorderSidebar([initial[0], initial[2]], parent: nil, index: 5)
        let reordered = [initial[1], initial[3], initial[4], initial[0], initial[2]]
        precondition(store.configuration.sidebarOrder == reordered)
        precondition(ConfigurationStore(defaults: defaults).configuration.sidebarOrder == reordered)
        var renamed = lights
        renamed[0].name = "ZZZ"
        try store.save(displayID: 3, lights: renamed)
        precondition(store.configuration.sidebarOrder == reordered)
        let group = try store.createGroup(name: "Room", memberIDs: [initial[0], initial[2]], sourceID: initial[0])
        let members = store.configuration.groups[0].memberIDs
        let beforeLights = try encoder.encode(store.configuration.lights)
        try store.reorderSidebar([members[0]], parent: group, index: 2)
        precondition(store.configuration.groups[0].memberIDs == Array(members.reversed()))
        precondition(try! encoder.encode(store.configuration.lights) == beforeLights)
        let saved = try encoder.encode(store.configuration)
        for operation in [
            { try store.reorderSidebar([members[0]], parent: nil, index: 0) },
            { try store.reorderSidebar([initial[1]], parent: group, index: 0) },
            { try store.reorderSidebar([initial[1], members[0]], parent: nil, index: 0) },
            { try store.reorderSidebar([initial[1]], parent: nil, index: 999) }
        ] {
            do { try operation(); preconditionFailure("Expected invalid destination") } catch {}
            precondition(try! encoder.encode(store.configuration) == saved)
        }
        let failing = ConfigurationStore(defaults: defaults, writeData: { _ in throw ConfigurationError.storageFailure })
        let failingBefore = try encoder.encode(failing.configuration)
        // Dropping back in place must not even attempt a write.
        try failing.reorderSidebar([group], parent: nil, index: failing.configuration.sidebarOrder.count)
        precondition(try! encoder.encode(failing.configuration) == failingBefore)
        do { try failing.reorderSidebar([group], parent: nil, index: 0); preconditionFailure("Expected storage error") } catch {}
        precondition(try! encoder.encode(failing.configuration) == failingBefore)
        // Decode old files with no ordering metadata; retain their original visual alphabetical order.
        var old = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        old.removeValue(forKey: "sidebarOrder")
        let migrated = try JSONDecoder().decode(AppConfiguration.self, from: JSONSerialization.data(withJSONObject: old))
        precondition(migrated.groups[0].memberIDs == [initial[0], initial[2]])
        let normalized = AppConfiguration(monitor: store.configuration.monitor, lights: lights,
                                          groups: store.configuration.groups,
                                          sidebarOrder: [group, group, UUID()])
        precondition(normalized.sidebarOrder.first == group)
        precondition(Set(normalized.sidebarOrder).count == normalized.sidebarOrder.count)
        precondition(!normalized.sidebarOrder.contains(members[0]))
        try store.moveLights([members[0]], to: nil)
        precondition(store.configuration.sidebarOrder.last == members[0])
        try store.setLightHidden(initial[1], hidden: true)
        precondition(!store.configuration.sidebarOrder.contains(initial[1]))
        try store.setLightHidden(initial[1], hidden: false)
        precondition(store.configuration.sidebarOrder.last == initial[1])
        // Folder headers and descendants must resolve to root-level slots,
        // including adjacent folders without an independent light between them.
        let otherGroup = UUID()
        let roots = [initial[1], group, otherGroup]
        let children = [group: members, otherGroup: [UUID()]]
        precondition(SidebarOrder.rootInsertion(roots: roots, children: children, hovered: group, afterHeader: false) == 1)
        precondition(SidebarOrder.rootInsertion(roots: roots, children: children, hovered: group, afterHeader: true) == 2)
        precondition(SidebarOrder.rootInsertion(roots: roots, children: children, hovered: members[0], afterHeader: true) == 2)
        precondition(SidebarOrder.rootInsertion(roots: roots, children: children, hovered: otherGroup, afterHeader: false) == 2)
        precondition(SidebarOrder.rootInsertion(roots: roots, children: children, hovered: otherGroup, afterHeader: true) == 3)
        precondition(SidebarOrder.rootInsertion(roots: roots, children: children, hovered: UUID(), afterHeader: true) == nil)
        print("PASS: root insertion works before, after and between folders, including expanded descendants")
        print("PASS: manual order migrates, persists, preserves settings and relative order; invalid and failed moves are atomic")
    }

}
