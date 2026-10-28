import AppKit

@main
struct RangeControlTests {
    @MainActor
    static func main() {
        let view = RangeSliderView(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        view.configure(minimum: 40, maximum: 80, domain: 0...100, title: "Monitor")
        view.layoutSubtreeIfNeeded()
        var changes: (Int, Int)?
        var commits = 0
        view.onChange = { changes = ($0, $1) }
        view.onCommit = { commits += 1 }

        view.minimumSlider.doubleValue = 100
        view.minimumSlider.sendAction(view.minimumSlider.action, to: view.minimumSlider.target)
        precondition(changes?.0 == 79 && changes?.1 == 80)
        precondition(commits == 1)
        _ = view.minimumSlider.accessibilityPerformDecrement()
        precondition(view.minimumSlider.doubleValue == 78)
        view.maximumSlider.doubleValue = 0
        view.maximumSlider.sendAction(view.maximumSlider.action, to: view.maximumSlider.target)
        precondition(changes?.0 == 78 && changes?.1 == 79)
        print("PASS: endpoints cannot cross and accessibility adjusts by one percent")

        view.configure(minimum: 0, maximum: 100, domain: 0...100, title: "Monitor")
        _ = view.minimumSlider.accessibilityPerformDecrement()
        _ = view.maximumSlider.accessibilityPerformIncrement()
        precondition(view.minimumSlider.doubleValue == 0 && view.maximumSlider.doubleValue == 100)
        view.configure(minimum: 1, maximum: 100, domain: 1...100, title: "Light")
        _ = view.minimumSlider.accessibilityPerformDecrement()
        precondition(view.minimumSlider.doubleValue == 1)
        precondition(view.minimumSlider.numberOfTickMarks == 0 && view.maximumSlider.numberOfTickMarks == 0)
        print("PASS: monitor/light domain limits and no tick marks")

        view.configure(minimum: 40, maximum: 80, domain: 0...100, title: "Monitor")
        let beforeTracking = commits
        view.minimumSlider.onBeginEditing?()
        view.minimumSlider.doubleValue = 52
        view.minimumSlider.sendAction(view.minimumSlider.action, to: view.minimumSlider.target)
        precondition(changes?.0 == 52 && commits == beforeTracking)
        view.minimumSlider.onEndEditing?()
        precondition(commits == beforeTracking + 1)
        print("PASS: drag updates values continuously and commits on release")

        let lowerCell = view.minimumSlider.cell as! NSSliderCell
        let upperCell = view.maximumSlider.cell as! NSSliderCell
        let lowerKnob = lowerCell.knobRect(flipped: view.minimumSlider.isFlipped)
        let upperKnob = upperCell.knobRect(flipped: view.maximumSlider.isFlipped)
        precondition(view.hitTest(NSPoint(x: lowerKnob.midX, y: lowerKnob.midY)) === view.minimumSlider)
        precondition(view.hitTest(NSPoint(x: upperKnob.midX, y: upperKnob.midY)) === view.maximumSlider)
        view.configure(minimum: 79, maximum: 80, domain: 0...100, title: "Monitor")
        let tightLower = lowerCell.knobRect(flipped: view.minimumSlider.isFlipped)
        let tightUpper = upperCell.knobRect(flipped: view.maximumSlider.isFlipped)
        precondition(view.hitTest(NSPoint(x: tightLower.midX, y: tightLower.midY)) === view.minimumSlider)
        precondition(view.hitTest(NSPoint(x: tightUpper.midX, y: tightUpper.midY)) === view.maximumSlider)
        print("PASS: both thumbs are reachable, including adjacent values")
    }
}
