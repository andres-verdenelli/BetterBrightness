import Foundation

@MainActor
private final class OffsetTestClock {
    var time: TimeInterval = 0
    final class Job {
        let due: TimeInterval
        let action: () -> Void
        var cancelled = false
        init(due: TimeInterval, action: @escaping () -> Void) { self.due = due; self.action = action }
    }
    var jobs: [Job] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> (() -> Void) {
        let job = Job(due: time + delay, action: action)
        jobs.append(job)
        return { job.cancelled = true }
    }
    func advance(_ delta: TimeInterval) {
        time += delta
        let ready = jobs.filter { $0.due <= time + 0.000001 && !$0.cancelled }
        jobs.removeAll { $0.due <= time + 0.000001 || $0.cancelled }
        ready.forEach { $0.action() }
    }
}

enum MenuOffsetTests {
    @MainActor static func run() throws {
        let suite = "BetterBrightness.OffsetTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var failWrites = false
        var writes = 0
        let store = ConfigurationStore(defaults: defaults, writeData: { data in
            if failWrites { throw ConfigurationError.storageFailure }
            writes += 1
            defaults.set(data, forKey: "betterBrightness.configuration")
        })
        let mapping = BrightnessMapping(monitorMin: 0, monitorMax: 100, lightMinPercent: 1, lightMaxPercent: 100)
        let a = LightConfiguration(name: "A", ip: "192.0.2.1", mapping: mapping, showInMenu: true)
        let b = LightConfiguration(name: "B", ip: "192.0.2.2", mapping: mapping, brightnessOffset: -10, showInMenu: true)
        try store.save(displayID: 3, lights: [a, b])
        let clock = OffsetTestClock()
        var sends: [(time: Double, id: UUID, value: Int)] = []
        let controller = BrightnessController(configurationStore: store, startsServices: false,
            send: { sends.append((clock.time, $1.id, $0)) }, now: { clock.time }, schedule: clock.schedule)
        func values(_ id: UUID) -> [Int] { sends.filter { $0.id == id }.map(\.value) }
        precondition(controller.disabledReason(for: a.id) == "Waiting for monitor brightness")
        controller.changeOffset(20, for: a.id)
        precondition(sends.isEmpty && controller.offset(for: a.id) == 0)
        controller.sendBrightnessToEnabledLights(50)
        sends.removeAll()
        let writesBefore = writes
        controller.changeOffset(1, for: a.id)
        precondition(values(a.id) == [mapping.dimmingValue(for: 50, offset: 1)])
        clock.advance(0.1)
        controller.changeOffset(10, for: a.id)
        controller.changeOffset(20, for: a.id)
        controller.sendBrightnessToEnabledLights(55)
        precondition(values(a.id).count == 1 && writes == writesBefore)
        clock.advance(0.199)
        precondition(values(a.id).count == 1)
        clock.advance(0.001)
        precondition(values(a.id).last == mapping.dimmingValue(for: 55, offset: 20))
        precondition(sends.filter { $0.id == a.id }.last!.time.distance(to: 0.3).magnitude < 0.000001)
        controller.changeOffset(25, for: a.id)
        controller.finishOffsetAdjustment(a.id)
        precondition(values(a.id).last == mapping.dimmingValue(for: 55, offset: 25))
        let finalCount = values(a.id).count
        clock.advance(1)
        controller.finishOffsetAdjustment(a.id)
        precondition(values(a.id).count == finalCount && writes == writesBefore + 1)
        precondition(ConfigurationStore(defaults: defaults).configuration.lights[0].brightnessOffset == 25)
        controller.sendBrightnessToEnabledLights(65)
        precondition(values(a.id).last == mapping.dimmingValue(for: 65, offset: 25))
        print("PASS: first send, 300ms shared monitor/slider throttle, latest pending value, immediate final, no duplicate final, one write and restart")

        try store.reorderSidebar([b.id], parent: nil, index: 0)
        precondition(controller.menuDestinations.map(\.id) == [b.id, a.id])
        controller.changeOffset(24, for: a.id)
        controller.changeOffset(23, for: a.id)
        var renamed = store.configuration.lights
        renamed[0].name = "Renamed"
        try store.save(displayID: 3, lights: renamed)
        precondition(controller.menuDestinations.last?.name == "Renamed" && controller.offset(for: a.id) == 23)
        controller.finishOffsetAdjustment(a.id)
        precondition(store.configuration.lights[0].brightnessOffset == 23)
        print("PASS: manual menu order and rename preserve an in-flight adjustment")

        controller.changeOffset(29, for: a.id)
        let beforeIdentical = values(a.id).count
        controller.changeOffset(29, for: a.id)
        controller.finishOffsetAdjustment(a.id)
        precondition(values(a.id).count == beforeIdentical)
        controller.changeOffset(10, for: a.id)
        controller.changeOffset(15, for: a.id)
        controller.pause()
        let pausedCount = sends.count
        clock.advance(1)
        controller.sendBrightnessToEnabledLights(30)
        controller.changeOffset(20, for: a.id)
        precondition(sends.count == pausedCount && controller.disabledReason(for: a.id) == "Sync paused")
        controller.resume()
        precondition(values(a.id).last == mapping.dimmingValue(for: 30, offset: 15))
        print("PASS: pause cancels queued sends, disables adjustment, resume uses latest monitor and retained offset")

        failWrites = true
        do {
            try controller.setSyncEnabled(false, for: a.id)
            preconditionFailure("Expected Sync save failure")
        } catch {}
        precondition(controller.syncEnabled(for: a.id))
        controller.changeOffset(-15, for: a.id)
        controller.finishOffsetAdjustment(a.id)
        precondition(controller.offsetSaveError != nil && controller.offset(for: a.id) == 15)
        precondition(values(a.id).last == mapping.dimmingValue(for: 30, offset: 15))
        failWrites = false
        controller.clearOffsetSaveError()
        print("PASS: failed gesture save reports error and reapplies persisted offset")

        controller.changeOffset(12, for: a.id)
        controller.changeOffset(22, for: a.id)
        var lights = store.configuration.lights
        lights[0].isEnabled = false
        try store.save(displayID: 3, lights: lights)
        let offCount = values(a.id).count
        clock.advance(1)
        controller.finishOffsetAdjustment(a.id)
        precondition(values(a.id).count == offCount && controller.menuDestinations.contains { $0.id == a.id })
        precondition(store.configuration.lights[0].showInMenu && controller.offset(for: a.id) == 15)
        lights = store.configuration.lights
        lights[0].isEnabled = true
        try store.save(displayID: 3, lights: lights)
        precondition(controller.menuDestinations.contains { $0.id == a.id } && controller.offset(for: a.id) == 15)
        lights = store.configuration.lights
        lights[0].isEnabled = true
        lights[0].showInMenu = false
        try store.save(displayID: 3, lights: lights)
        precondition(controller.offset(for: a.id) == 0 && !controller.menuDestinations.contains { $0.id == a.id })
        precondition(values(a.id).last == mapping.dimmingValue(for: 30))
        print("PASS: Sync off cancels drag; removing menu access resets offset and reapplies curve")

        var unavailable = store.configuration.lights
        unavailable[1].isIPAddressVerified = false
        try store.save(displayID: 3, lights: unavailable)
        let unavailableCount = values(b.id).count
        controller.changeOffset(10, for: b.id)
        clock.advance(1)
        precondition(values(b.id).count == unavailableCount && controller.disabledReason(for: b.id) == "Waiting for rediscovery")
        unavailable[1].isIPAddressVerified = true
        try store.save(displayID: 3, lights: unavailable)

        let groupID = try store.createGroup(name: "Group", memberIDs: [a.id, b.id], sourceID: a.id)
        var group = store.configuration.groups[0]
        group.showInMenu = true
        group.brightnessOffset = -20
        try store.updateGroup(group)
        precondition(store.configuration.lights.allSatisfy { !$0.showInMenu && $0.brightnessOffset == 0 })
        try controller.setSyncEnabled(false, for: groupID)
        group = store.configuration.groups[0]
        precondition(controller.menuDestinations.contains { $0.id == groupID } && controller.disabledReason(for: groupID) == "Sync is off")
        precondition(controller.offset(for: groupID) == -20 && store.configuration.groups[0].showInMenu)
        group.isEnabled = true
        try store.updateGroup(group)
        precondition(controller.menuDestinations.contains { $0.id == groupID })
        sends.removeAll()
        controller.changeOffset(10, for: groupID)
        precondition(sends.count == 2 && Set(sends.map(\.value)).count == 1)
        controller.finishOffsetAdjustment(groupID)
        try store.moveLights([a.id], to: nil)
        precondition(store.configuration.lights[0].brightnessOffset == 10 && store.configuration.lights[0].showInMenu)
        precondition(store.configuration.effectiveLights[1].brightnessOffset == 10)
        try store.ungroup(groupID)
        precondition(store.configuration.lights.allSatisfy { $0.brightnessOffset == 10 && $0.showInMenu })
        try store.setLightHidden(a.id, hidden: true)
        precondition(store.configuration.lights[0].brightnessOffset == 0 && !store.configuration.lights[0].showInMenu)
        try store.setLightHidden(a.id, hidden: false)
        precondition(!store.configuration.lights[0].isEnabled)
        try store.removeLight(b.id)
        precondition(!controller.menuDestinations.contains { $0.id == b.id })
        print("PASS: group offset/fanout, entry, exit, ungroup, hide/restore and deletion")

        precondition(mapping.dimmingValue(for: 0, offset: -30) == 10)
        precondition(mapping.dimmingValue(for: 100, offset: 30) == 100)
        precondition(mapping.dimmingValue(for: 50, offset: 0) == mapping.dimmingValue(for: 50))
        let curve = BrightnessMapping(monitorMin: 40, monitorMax: 80, lightMinPercent: 10, lightMaxPercent: 70)
        precondition(curve.visiblePercentage(for: 60) == 40)
        precondition(curve.dimmingValue(for: 60, offset: 10) == BrightnessMapping.protocolDimmingValue(forVisiblePercentage: 50))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.configuration)) as! [String: Any]
        var oldLights = json["lights"] as! [[String: Any]]
        oldLights[0].removeValue(forKey: "brightnessOffset")
        oldLights[0].removeValue(forKey: "showInMenu")
        json["lights"] = oldLights
        json["groups"] = [["id": UUID().uuidString, "name": "Legacy", "memberIDs": [a.id.uuidString], "isEnabled": true,
                           "mapping": ["monitorMin": 0, "monitorMax": 100, "lightMinPercent": 1, "lightMaxPercent": 100]]]
        let legacy = try JSONDecoder().decode(AppConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        precondition(legacy.lights[0].brightnessOffset == 0 && !legacy.lights[0].showInMenu)
        precondition(legacy.groups[0].brightnessOffset == 0 && !legacy.groups[0].showInMenu)
        try store.save(displayID: 7, lights: store.configuration.lights)
        precondition(controller.lastMonitorBrightness == nil)
        print("PASS: visible-before-protocol calculation, bounds, zero, legacy light/group migration and display change invalidation")
    }
}
