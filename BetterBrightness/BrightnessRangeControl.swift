import AppKit
import SwiftUI

/// Two native slider thumbs sharing one track and one percentage scale.
struct BrightnessRangeControl: NSViewRepresentable {
    @Binding var minimum: Int
    @Binding var maximum: Int
    let domain: ClosedRange<Int>
    let title: String
    let onCommit: () -> Void

    func makeNSView(context: Context) -> RangeSliderView {
        RangeSliderView()
    }

    func updateNSView(_ view: RangeSliderView, context: Context) {
        view.configure(minimum: minimum, maximum: maximum, domain: domain, title: title)
        view.onChange = { lower, upper in
            minimum = lower
            maximum = upper
        }
        view.onCommit = onCommit
    }
}

final class RangeSliderView: NSView {
    let minimumSlider = RangeThumbSlider(frame: .zero)
    let maximumSlider = RangeThumbSlider(frame: .zero)
    var onChange: ((Int, Int) -> Void)?
    var onCommit: (() -> Void)?
    private var isTracking = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for slider in [minimumSlider, maximumSlider] {
            slider.cell = RangeThumbCell()
            slider.sliderType = .linear
            slider.isVertical = false
            slider.numberOfTickMarks = 0
            slider.isContinuous = true
            slider.target = self
            slider.action = #selector(valueChanged(_:))
            slider.onBeginEditing = { [weak self] in self?.isTracking = true }
            slider.onEndEditing = { [weak self] in
                self?.isTracking = false
                self?.onCommit?()
            }
            addSubview(slider)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(minimum: Int, maximum: Int, domain: ClosedRange<Int>, title: String) {
        for slider in [minimumSlider, maximumSlider] {
            slider.minValue = Double(domain.lowerBound)
            slider.maxValue = Double(domain.upperBound)
        }
        minimumSlider.doubleValue = Double(minimum)
        maximumSlider.doubleValue = Double(maximum)
        minimumSlider.setAccessibilityLabel("\(title) minimum")
        maximumSlider.setAccessibilityLabel("\(title) maximum")
        updateAccessibilityValues()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        minimumSlider.frame = bounds
        maximumSlider.frame = bounds
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 28) }

    private func knobRect(for slider: NSSlider) -> NSRect {
        (slider.cell as? NSSliderCell)?.knobRect(flipped: slider.isFlipped) ?? .zero
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let minimumDistance = abs(local.x - knobRect(for: minimumSlider).midX)
        let maximumDistance = abs(local.x - knobRect(for: maximumSlider).midX)
        // Choosing the nearest thumb also keeps tightly spaced endpoints reachable.
        return minimumDistance <= maximumDistance ? minimumSlider : maximumSlider
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let cell = minimumSlider.cell as? NSSliderCell else { return }
        let bar = cell.barRect(flipped: minimumSlider.isFlipped)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
        let lower = knobRect(for: minimumSlider).midX
        let upper = knobRect(for: maximumSlider).midX
        let selection = NSRect(x: lower, y: bar.minY, width: max(0, upper - lower), height: bar.height)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: selection, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
    }

    @objc private func valueChanged(_ sender: NSSlider) {
        if sender === minimumSlider {
            minimumSlider.doubleValue = min(
                max(sender.doubleValue.rounded(), sender.minValue),
                maximumSlider.doubleValue - 1
            )
        } else {
            maximumSlider.doubleValue = max(
                min(sender.doubleValue.rounded(), sender.maxValue),
                minimumSlider.doubleValue + 1
            )
        }
        updateAccessibilityValues()
        needsDisplay = true
        onChange?(Int(minimumSlider.doubleValue), Int(maximumSlider.doubleValue))
        if !isTracking { onCommit?() }
    }

    private func updateAccessibilityValues() {
        minimumSlider.setAccessibilityValueDescription("\(Int(minimumSlider.doubleValue)) percent")
        maximumSlider.setAccessibilityValueDescription("\(Int(maximumSlider.doubleValue)) percent")
    }
}

private final class RangeThumbCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        // The containing view draws the single shared track.
    }
}

final class RangeThumbSlider: NSSlider {
    var onBeginEditing: (() -> Void)?
    var onEndEditing: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onBeginEditing?()
        super.mouseDown(with: event)
        onEndEditing?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 125: adjust(by: -1)
        case 124, 126: adjust(by: 1)
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool { adjust(by: 1); return true }
    override func accessibilityPerformDecrement() -> Bool { adjust(by: -1); return true }

    private func adjust(by delta: Int) {
        doubleValue = min(max(doubleValue + Double(delta), minValue), maxValue)
        sendAction(action, to: target)
    }
}
