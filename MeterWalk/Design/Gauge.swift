//
//  Gauge.swift
//  MeterWalk
//
//  Daily use against last year on a half-dial. Last year's rate sits straight
//  up; everything to the right of it is the red zone. The needle swings in
//  on a spring and overshoots before settling.
//

import SwiftUI

struct UsageGauge: View {
    /// Current daily use.
    let value: Double
    /// Last year's daily use (or the first-months baseline).
    let baseline: Double

    @State private var needleFraction: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The dial runs from zero to twice the baseline.
    private var scaleMax: Double { max(baseline * 2, 0.0001) }
    private var targetFraction: Double { min(1.04, max(0, value / scaleMax)) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let radius = min(width / 2, proxy.size.height) - 6
            let center = CGPoint(x: width / 2, y: radius + 6)

            ZStack {
                // Red sector: above last year.
                ArcBand(center: center, radius: radius - 2, thickness: 10, from: 0.5, to: 1)
                    .fill(Palette.red.opacity(0.9))
                ArcBand(center: center, radius: radius - 2, thickness: 10, from: 0, to: 0.5)
                    .fill(Palette.ghost)

                GaugeTicks(center: center, radius: radius - 16, count: 40)
                    .stroke(Palette.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .butt))

                // Last year marker.
                Path { path in
                    path.move(to: CGPoint(x: center.x, y: center.y - radius + 18))
                    path.addLine(to: CGPoint(x: center.x, y: center.y - radius - 4))
                }
                .stroke(Palette.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                Needle(center: center, length: radius - 22, fraction: needleFraction)
                    .stroke(Palette.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                Circle()
                    .fill(Palette.yellow)
                    .frame(width: 12, height: 12)
                    .position(center)
                Circle()
                    .fill(Palette.lcd)
                    .frame(width: 4, height: 4)
                    .position(center)
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .onAppear { swing(to: targetFraction) }
        .onChange(of: value) { _ in swing(to: targetFraction) }
        .onChange(of: baseline) { _ in swing(to: targetFraction) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily use gauge")
        .accessibilityValue(Text("\(NumberText.rate(value)) a day against \(NumberText.rate(baseline))"))
    }

    private func swing(to fraction: Double) {
        if reduceMotion {
            needleFraction = fraction
            return
        }
        needleFraction = 0
        DispatchQueue.main.async {
            withAnimation(Motion.needle) { needleFraction = fraction }
        }
    }
}

/// Converts a 0…1 position on the half-dial to an angle, left to right.
private func dialAngle(_ fraction: Double) -> Angle {
    .degrees(180 + 180 * fraction)
}

private struct ArcBand: Shape {
    let center: CGPoint
    let radius: CGFloat
    let thickness: CGFloat
    let from: Double
    let to: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: dialAngle(from), endAngle: dialAngle(to), clockwise: false)
        path.addArc(center: center, radius: radius - thickness, startAngle: dialAngle(to), endAngle: dialAngle(from), clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct GaugeTicks: Shape {
    let center: CGPoint
    let radius: CGFloat
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0...count {
            let fraction = Double(i) / Double(count)
            let angle = CGFloat(dialAngle(fraction).radians)
            let major = i % 5 == 0
            let inner = radius - (major ? 12 : 6)
            path.move(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
        }
        return path
    }
}

private struct Needle: Shape {
    let center: CGPoint
    let length: CGFloat
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let angle = CGFloat(dialAngle(fraction).radians)
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length))
        return path
    }
}
