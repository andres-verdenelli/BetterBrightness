import SwiftUI

/// One shared constraint for typed values and steppers.
func boundedBrightness(_ value: Int, lower: Int, upper: Int) -> Int {
    min(max(value, lower), upper)
}

struct FollowBrightnessEditor: View {
    @Binding var monitorMin: Int
    @Binding var monitorMax: Int
    @Binding var lightMin: Int
    @Binding var lightMax: Int
    let onCommit: () -> Void

    private var dimMonitor: Binding<Int> {
        Binding(get: { monitorMin }, set: { monitorMin = boundedBrightness($0, lower: 0, upper: monitorMax - 1) })
    }
    private var brightMonitor: Binding<Int> {
        Binding(get: { monitorMax }, set: { monitorMax = boundedBrightness($0, lower: monitorMin + 1, upper: 100) })
    }
    private var dimLight: Binding<Int> {
        Binding(get: { lightMin }, set: { lightMin = boundedBrightness($0, lower: 1, upper: lightMax - 1) })
    }
    private var brightLight: Binding<Int> {
        Binding(get: { lightMax }, set: { lightMax = boundedBrightness($0, lower: lightMin + 1, upper: 100) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            situation("Dim light", monitor: dimMonitor, light: dimLight)
            Divider()
            situation("Bright light", monitor: brightMonitor, light: brightLight)
            Text("The light increases gradually between these points and stays at its dim or bright limit outside them.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        }
        .padding(.vertical, 6)
    }

    private func situation(_ title: String, monitor: Binding<Int>, light: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    monitorPhrase(title, value: monitor)
                    lightPhrase(title, value: light)
                }
                VStack(alignment: .leading, spacing: 8) {
                    monitorPhrase(title, value: monitor)
                    lightPhrase(title, value: light)
                }
            }
        }
    }

    private func monitorPhrase(_ title: String, value: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Text("When the monitor reaches")
            PercentageEditor(value: value, title: "\(title) monitor brightness", onCommit: onCommit)
        }
    }

    private func lightPhrase(_ title: String, value: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Text("set the light to")
            PercentageEditor(value: value, title: "\(title) light brightness", onCommit: onCommit)
        }
    }

}

private struct PercentageEditor: View {
    @Binding var value: Int
    let title: String
    let onCommit: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 2) {
            TextField(title, text: $text)
                .labelsHidden().textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing).frame(width: 40)
                .focused($focused).onSubmit(commit)
                .onChange(of: focused) { wasFocused, isFocused in
                    if wasFocused && !isFocused { commit() }
                }
                .onKeyPress(.upArrow) { adjust(1); return .handled }
                .onKeyPress(.downArrow) { adjust(-1); return .handled }
            Text("%")
            Stepper(title, onIncrement: { adjust(1) }, onDecrement: { adjust(-1) })
                .labelsHidden().fixedSize()
        }
        .monospacedDigit()
        .onAppear { text = String(value) }
        .onChange(of: value) { _, newValue in text = String(newValue) }
    }

    private func commit() {
        if let number = Int(text.trimmingCharacters(in: .whitespaces)) { value = number }
        text = String(value)
        onCommit()
    }

    private func adjust(_ delta: Int) {
        value += delta
        text = String(value)
        onCommit()
    }
}
