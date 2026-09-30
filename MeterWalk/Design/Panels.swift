//
//  Panels.swift
//  MeterWalk
//
//  The meter-panel look: a navy panel with a 2px border, and inside it a
//  recessed LCD window with a shadow along its top edge.
//

import SwiftUI

struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
                    .fill(Palette.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
                    .strokeBorder(Palette.ghost, lineWidth: Metrics.borderWidth)
            )
    }
}

/// The sunken display window.
struct RecessedDisplay<Content: View>: View {
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RecessedShape())
    }
}

struct RecessedShape: View {
    var radius: CGFloat = Metrics.displayRadius

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                Palette.lcd
                    .shadow(.inner(color: .black.opacity(0.85), radius: 1.5, x: 0, y: 2))
            )
    }
}

// MARK: - LCD readout

/// Digits on an LCD with the unlit "8" segments behind them. Digits roll up
/// from zero one place at a time when the readout appears.
struct LCDReadout: View {
    let text: String
    var size: CGFloat = 48
    var color: Color = Palette.yellow
    var rollFromZero = true
    /// Optional unit printed small after the digits.
    var unit: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var characters: [Character] { Array(text) }
    private var cellWidth: CGFloat { size * 0.62 }
    private var cellHeight: CGFloat { size * 1.18 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ZStack(alignment: .leading) {
                cells(ghost: true)
                cells(ghost: false)
            }
            .fixedSize()
            // Each rolling digit is a hidden column of ten numbers; without an
            // explicit baseline, text alignment would use the top one.
            .alignmentGuide(.firstTextBaseline) { $0[.top] + size * 0.93 }
            .alignmentGuide(.lastTextBaseline) { $0[.top] + size * 0.93 }
            if let unit {
                Text(unit)
                    .font(.system(size: max(12, size * 0.3), weight: .semibold))
                    .foregroundStyle(color.opacity(0.75))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        let trimmed = text.drop { $0 == "0" }
        let value = trimmed.isEmpty || trimmed.first == "." ? "0" + trimmed : String(trimmed)
        return unit.map { "\(value) \($0)" } ?? value
    }

    private func cells(ghost: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                cell(character, index: index, ghost: ghost)
                    .frame(width: character == "." ? cellWidth * 0.42 : cellWidth, height: cellHeight)
            }
        }
    }

    @ViewBuilder
    private func cell(_ character: Character, index: Int, ghost: Bool) -> some View {
        if character == "." {
            // A drawn segment dot on the baseline; a text "." in a narrow
            // cell is squeezed by its font's wide advance.
            let diameter = max(3, size * 0.15)
            Color.clear.overlay(alignment: .top) {
                Circle()
                    .fill(ghost ? Palette.ghost : color)
                    .frame(width: diameter, height: diameter)
                    .offset(y: size * 0.93 - diameter)
            }
        } else if ghost {
            Text(character.isNumber ? "8" : String(character))
                .font(TypeScale.mono(size))
                .foregroundStyle(Palette.ghost)
        } else if let digit = character.wholeNumberValue {
            RollingDigit(
                digit: digit,
                size: size,
                height: cellHeight,
                color: color,
                delay: Double(index) * Motion.digitDelay,
                animate: rollFromZero && !reduceMotion
            )
        } else {
            Text(String(character))
                .font(TypeScale.mono(size))
                .foregroundStyle(color)
        }
    }
}

private struct RollingDigit: View {
    let digit: Int
    let size: CGFloat
    let height: CGFloat
    let color: Color
    let delay: Double
    let animate: Bool

    @State private var shown: Int?

    var body: some View {
        let current = shown ?? (animate ? 0 : digit)
        VStack(spacing: 0) {
            ForEach(0..<10, id: \.self) { n in
                Text("\(n)")
                    .font(TypeScale.mono(size))
                    .foregroundStyle(color)
                    .frame(height: height)
            }
        }
        .offset(y: -CGFloat(current) * height + 4.5 * height)
        .frame(height: height)
        .clipped()
        .onAppear {
            guard animate else {
                shown = digit
                return
            }
            shown = 0
            withAnimation(.easeOut(duration: 0.5).delay(delay)) {
                shown = digit
            }
        }
        .onChange(of: digit) { newValue in
            if animate {
                withAnimation(.easeOut(duration: 0.4).delay(delay)) { shown = newValue }
            } else {
                shown = newValue
            }
        }
    }
}

/// An LCD readout that shrinks to fit the width it is given.
struct FittedLCD: View {
    let text: String
    var maxSize: CGFloat = 48
    var color: Color = Palette.yellow
    var rollFromZero = true
    var unit: String? = nil

    var body: some View {
        GeometryReader { proxy in
            let unitWidth: CGFloat = unit == nil ? 0 : maxSize * 0.3 * CGFloat(unit!.count) * 0.7 + 8
            let count = CGFloat(text.count) - (text.contains(".") ? 0.58 : 0)
            let fitted = (proxy.size.width - unitWidth) / max(1, count * 0.62)
            LCDReadout(text: text, size: min(maxSize, max(18, fitted)), color: color, rollFromZero: rollFromZero, unit: unit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: maxSize * 1.18)
    }
}
