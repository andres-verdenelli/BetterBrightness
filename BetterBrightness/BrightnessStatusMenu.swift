import AppKit
import Combine
import SwiftUI

/// Keep NSMenu tracking active while NSSlider runs its own mouse tracking loop.
@MainActor
final class BrightnessStatusMenu: NSObject, NSMenuDelegate {
    private let controller: BrightnessController
    private let item: NSStatusItem
    private let menu = NSMenu()
    private var subscription: AnyCancellable?
    private var rows: [UUID: OffsetMenuRow] = [:]
    private var pauseItem: NSMenuItem!
    private var settingsHost: NSHostingView<SettingsActionBridge>?
    private var openSettingsAction: (() -> Void)?

    init(controller: BrightnessController) {
        self.controller = controller
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "BetterBrightness")
        item.menu = menu
        menu.delegate = self
        subscription = controller.objectWillChange.sink { [weak self] in
            // Published properties notify before mutation; refresh on the next run-loop turn,
            // including NSMenu's event-tracking mode.
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        let host = NSHostingView(rootView: SettingsActionBridge { [weak self] action in
            self?.openSettingsAction = action
        })
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        host.alphaValue = 0
        item.button?.addSubview(host)
        settingsHost = host
        rebuild()
    }

#if DEBUG
    func showPreviewMenu() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }),
              let view = window.contentView else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.width - 320, y: view.bounds.height - 50), in: view)
    }
#endif

    func menuWillOpen(_ menu: NSMenu) { rebuild() }
    func menuDidClose(_ menu: NSMenu) {
        for id in rows.keys { controller.finishOffsetAdjustment(id) }
    }

    private func rebuild() {
        menu.removeAllItems()
        rows.removeAll()
        pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        for (index, destination) in controller.menuDestinations.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            let row = OffsetMenuRow(id: destination.id, name: destination.name, controller: controller)
            rows[destination.id] = row
            let entry = NSMenuItem()
            entry.view = row
            menu.addItem(entry)
        }
        if !rows.isEmpty { menu.addItem(.separator()) }
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit BetterBrightness", action: #selector(quitApp), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quit.target = self
        menu.addItem(quit)
        refresh()
    }

    private func refresh() {
        item.button?.image = NSImage(systemSymbolName: controller.isPaused ? "sun.max" : "sun.max.fill",
                                     accessibilityDescription: "BetterBrightness")
        pauseItem.title = controller.isPaused ? "Resume" : "Pause"
        pauseItem.image = NSImage(systemSymbolName: controller.isPaused ? "play.fill" : "pause.fill", accessibilityDescription: nil)
        // Never replace a view under the mouse during a gesture.
        for row in rows.values { row.refresh() }
        if let message = controller.offsetSaveError {
            controller.clearOffsetSaveError()
            menu.cancelTracking()
            let alert = NSAlert()
            alert.messageText = "Brightness adjustment could not be saved"
            alert.informativeText = message + "\nThe saved adjustment has been restored."
            alert.runModal()
        }
    }

    @objc private func showSettings() {
        menu.cancelTracking()
        NSApp.activate(ignoringOtherApps: true)
        openSettingsAction?()
    }

    @objc private func togglePause() { controller.togglePause() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}

/// Capture the scene-aware action without replacing a native menu row with a custom view.
private struct SettingsActionBridge: View {
    @Environment(\.openSettings) private var openSettings
    let onReady: (@escaping () -> Void) -> Void
    var body: some View {
        Color.clear.onAppear { onReady { openSettings() } }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

@MainActor
private final class OffsetMenuRow: NSView {
    private let id: UUID
    private let controller: BrightnessController
    private let syncSwitch = NSSwitch()
    private let nameLabel: NSTextField
    private let bubble = OffsetBubble(frame: NSRect(x: 0, y: 0, width: 44, height: 24))
    private let slider = GestureSlider(value: 0, minValue: -30, maxValue: 30, target: nil, action: nil)

    init(id: UUID, name: String, controller: BrightnessController) {
        self.id = id
        self.controller = controller
        nameLabel = NSTextField(labelWithString: name)
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 94))
        nameLabel.frame = NSRect(x: 16, y: 69, width: 212, height: 18)
        nameLabel.lineBreakMode = .byTruncatingTail
        syncSwitch.wantsLayer = true
        syncSwitch.controlSize = .small
        syncSwitch.frame = NSRect(x: 248, y: 68, width: 36, height: 20)
        syncSwitch.target = self
        syncSwitch.action = #selector(syncChanged)
        syncSwitch.setAccessibilityLabel("Sync \(name)")
        slider.cell = OffsetSliderCell()
        slider.minValue = -30
        slider.maxValue = 30
        slider.frame = NSRect(x: 16, y: 40, width: 268, height: 25)
        slider.numberOfTickMarks = 3
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.setAccessibilityLabel("\(name) brightness offset")
        slider.trackingChanged = { [weak self] tracking in
            guard let self else { return }
            self.bubble.isHidden = !tracking
            if tracking { self.updateBubble() }
        }
        bubble.isHidden = true
        slider.didFinish = { [weak self] in
            guard let self else { return }
            self.controller.finishOffsetAdjustment(self.id)
        }
        for view in [nameLabel, slider, syncSwitch, bubble] { addSubview(view) }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh() {
        let offset = controller.offset(for: id)
        slider.doubleValue = Double(offset)
        let reason = controller.disabledReason(for: id)
        slider.isEnabled = reason == nil
        if reason != nil { bubble.isHidden = true }
        let height: CGFloat = 64
        setFrameSize(NSSize(width: frame.width, height: height))
        nameLabel.frame.origin.y = height - 25
        syncSwitch.frame.origin.y = height - 26
        syncSwitch.state = controller.syncEnabled(for: id) ? .on : .off
        slider.needsDisplay = true
        slider.frame.origin.y = height - 54
        updateBubble()
    }

    private func updateBubble() {
        let knob = slider.convert(slider.knobFrame, to: self)
        let x = min(max(knob.midX - 22, 8), bounds.width - 52)
        bubble.frame.origin = NSPoint(x: x, y: knob.maxY + 4)
        let value = controller.offset(for: id)
        bubble.text = value == 0 ? "0" : value < 0 ? "−\(-value)" : "+\(value)"
    }

    @objc private func syncChanged() {
        do { try controller.setSyncEnabled(syncSwitch.state == .on, for: id) }
        catch {
            refresh()
            enclosingMenuItem?.menu?.cancelTracking()
            let alert = NSAlert()
            alert.messageText = "Sync could not be saved"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }

    @objc private func changed() {
        slider.doubleValue = slider.doubleValue.rounded()
        controller.changeOffset(slider.integerValue, for: id)
        refresh()
    }


}

private final class GestureSlider: NSSlider {
    var didFinish: (() -> Void)?
    var trackingChanged: ((Bool) -> Void)?
    var knobFrame: NSRect { (cell as? NSSliderCell)?.knobRect(flipped: isFlipped) ?? .zero }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        trackingChanged?(true)
        defer { trackingChanged?(false); didFinish?() }
        super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        didFinish?()
    }
    override func accessibilityPerformIncrement() -> Bool {
        let result = super.accessibilityPerformIncrement()
        didFinish?()
        return result
    }
    override func accessibilityPerformDecrement() -> Bool {
        let result = super.accessibilityPerformDecrement()
        didFinish?()
        return result
    }
}

/// A non-interactive value label; drawing locally keeps mouse tracking in NSSlider.
private final class OffsetBubble: NSView {
    var text = "0" { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

/// Keep native knob/tracking; only the signed offset segment changes its drawing.
private final class OffsetSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        guard doubleValue != 0 else { return }
        let center = rect.midX
        let knobX = knobRect(flipped: flipped).midX
        let segment = NSRect(x: min(center, knobX), y: track.minY, width: abs(knobX - center), height: track.height)
        (isEnabled ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setFill()
        NSBezierPath(roundedRect: segment, xRadius: 2, yRadius: 2).fill()
    }
}
