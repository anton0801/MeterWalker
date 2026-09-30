//
//  Buttons.swift
//  MeterWalk
//

import SwiftUI

/// Yellow, full width, 56pt.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(isEnabled ? Palette.background : Palette.tertiaryText)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous)
                    .fill(isEnabled ? Palette.yellow : Palette.ghost)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Blue outline, full width, 56pt.
struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = Palette.blue
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous)
                    .fill(configuration.isPressed ? color.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous)
                    .strokeBorder(color, lineWidth: 2)
            )
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
    }
}

/// Small text-weight action used inside panels.
struct InlineButtonStyle: ButtonStyle {
    var color: Color = Palette.blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.bodyEmphasis)
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Round 40pt icon button for screen headers.
struct IconButton: View {
    let symbol: String
    let label: String
    var color: Color = Palette.white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Palette.panel))
                .overlay(Circle().strokeBorder(Palette.ghost, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var destructive: SecondaryButtonStyle { SecondaryButtonStyle(color: Palette.red) }
}
