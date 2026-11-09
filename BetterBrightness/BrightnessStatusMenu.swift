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
    private var settingsHost: NSHostingView<NativeSettingsLink>?

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
        rebuild()
    }

#if DEBUG
    func showPreviewMenu() {
        guard let view = NSApp.keyWindow?.contentView else { return }
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
        for destination in controller.menuDestinations {
            let row = OffsetMenuRow(id: destination.id, name: destination.name, controller: controller)
            rows[destination.id] = row
            let entry = NSMenuItem()
            entry.view = row
            menu.addItem(entry)
        }
        if !rows.isEmpty { menu.addItem(.separator()) }
        // Use SwiftUI's scene-aware Settings action inside the native menu.
        let settings = NSMenuItem()
        let host = NSHostingView(rootView: NativeSettingsLink(onOpen: { [weak self] in self?.menu.cancelTracking() }))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 30)
        settingsHost = host
        settings.view = host
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit BetterBrightness", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        refresh()
    }

    private func refresh() {
        item.button?.image = NSImage(systemSymbolName: controller.isPaused ? "sun.max" : "sun.max.fill",
                                     accessibilityDescription: "BetterBrightness")
        pauseItem.title = controller.isPaused ? "Resume" : "Pause"
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

    @objc private func togglePause() { controller.togglePause() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}

private struct NativeSettingsLink: View {
    @Environment(\.openSettings) private var openSettings
    let onOpen: () -> Void
    var body: some View {
        Button {
            onOpen()
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            HStack { Text("Settings…"); Spacer() }
                .frame(width: 252, alignment: .leading).padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private final class OffsetMenuRow: NSView {
    private let id: UUID
    private let controller: BrightnessController
    private let nameLabel: NSTextField
    private let valueLabel = NSTextField(labelWithString: "0")
    private let reasonLabel = NSTextField(labelWithString: "")
    private let slider = GestureSlider(value: 0, minValue: -30, maxValue: 30, target: nil, action: nil)
    private let scale = NSStackView()

    init(id: UUID, name: String, controller: BrightnessController) {
        self.id = id
        self.controller = controller
        nameLabel = NSTextField(labelWithString: name)
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 94))
        nameLabel.frame = NSRect(x: 16, y: 69, width: 212, height: 18)
        nameLabel.lineBreakMode = .byTruncatingTail
        valueLabel.frame = NSRect(x: 236, y: 69, width: 48, height: 18)
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        slider.frame = NSRect(x: 16, y: 40, width: 268, height: 25)
        slider.numberOfTickMarks = 3
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.setAccessibilityLabel("\(name) brightness offset")
        slider.didFinish = { [weak self] in
            guard let self else { return }
            self.controller.finishOffsetAdjustment(self.id)
        }
        scale.orientation = .horizontal
        scale.distribution = .equalSpacing
        scale.frame = NSRect(x: 20, y: 12, width: 260, height: 18)
        for text in ["−30", "0", "+30"] {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            scale.addArrangedSubview(label)
        }
        addSubview(scale)
        reasonLabel.frame = NSRect(x: 16, y: 9, width: 268, height: 24)
        reasonLabel.font = .systemFont(ofSize: 11)
        reasonLabel.textColor = .secondaryLabelColor
        for view in [nameLabel, valueLabel, slider, reasonLabel] { addSubview(view) }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh() {
        let offset = controller.offset(for: id)
        slider.doubleValue = Double(offset)
        valueLabel.stringValue = String(format: "%+d pt", offset)
        let reason = controller.disabledReason(for: id)
        slider.isEnabled = reason == nil
        reasonLabel.stringValue = reason ?? ""
        scale.isHidden = reason != nil
    }

    @objc private func changed() {
        slider.doubleValue = slider.doubleValue.rounded()
        controller.changeOffset(slider.integerValue, for: id)
        refresh()
    }


}

private final class GestureSlider: NSSlider {
    var didFinish: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        didFinish?()
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
