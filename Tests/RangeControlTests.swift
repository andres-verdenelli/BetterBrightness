import Foundation

@main
struct RangeControlTests {
    static func main() {
        // Every possible opposing endpoint, including adjacent points and domain edges.
        for upper in 1...100 {
            for proposed in -10...110 {
                let actual = boundedBrightness(proposed, lower: 0, upper: upper - 1)
                precondition(actual >= 0 && actual < upper)
                if (0..<upper).contains(proposed) { precondition(actual == proposed) }
            }
        }
        for lower in 1...99 {
            for proposed in -10...110 {
                let actual = boundedBrightness(proposed, lower: lower + 1, upper: 100)
                precondition(actual > lower && actual <= 100)
                if ((lower + 1)...100).contains(proposed) { precondition(actual == proposed) }
            }
        }
        precondition(boundedBrightness(0, lower: 1, upper: 99) == 1)
        precondition(boundedBrightness(100, lower: 1, upper: 99) == 99)
        precondition(boundedBrightness(40, lower: 0, upper: 79) == 40)
        print("PASS: shared field/stepper constraints preserve valid values, 1% gaps, and domain edges")
    }
}
