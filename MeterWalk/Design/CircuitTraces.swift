//
//  CircuitTraces.swift
//  MeterWalk
//
//  Thin circuit-board traces with square corners and round pads, laid behind
//  empty states and gauges. The layout is seeded so it never shifts between
//  renders.
//

import SwiftUI

struct CircuitTraces: View {
    var seed: UInt64 = 11
    /// Roughly how many traces per 100pt of width.
    var density: Double = 1.4
    var color: Color = Palette.ghost

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            var rng = SeededRandom(seed: seed)
            let count = max(3, Int(Double(size.width) / 100 * density))
            let grid: CGFloat = 12
            let snap: (CGFloat) -> CGFloat = { ($0 / grid).rounded() * grid }

            for _ in 0..<count {
                let fromLeft = rng.nextBool()
                var point = CGPoint(
                    x: fromLeft ? -4 : size.width + 4,
                    y: snap(CGFloat(rng.nextDouble()) * size.height)
                )
                var path = Path()
                path.move(to: point)
                let segments = 2 + Int(rng.next() % 3)
                var horizontal = true
                for _ in 0..<segments {
                    if horizontal {
                        let length = snap(CGFloat(24 + rng.nextDouble() * Double(size.width) * 0.35))
                        point.x += fromLeft ? length : -length
                    } else {
                        let length = snap(CGFloat(12 + rng.nextDouble() * 60))
                        let up = rng.nextBool()
                        point.y = min(size.height - 8, max(8, point.y + (up ? -length : length)))
                    }
                    path.addLine(to: point)
                    horizontal.toggle()
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter))

                // Pad at the end of the trace, sometimes a via along it.
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(color))
                if rng.nextDouble() < 0.4 {
                    let via = CGPoint(x: point.x + (fromLeft ? 14 : -14), y: point.y)
                    context.stroke(Path(ellipseIn: CGRect(x: via.x - 3, y: via.y - 3, width: 6, height: 6)), with: .color(color), lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// SplitMix64: small, fast and the same on every device.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func nextBool() -> Bool { next() & 1 == 0 }

    /// A seed that is the same for the same text on every launch.
    static func stableSeed(_ text: String) -> UInt64 {
        text.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
    }
}
