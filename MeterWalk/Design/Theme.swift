//
//  Theme.swift
//  MeterWalk
//
//  Night-panel navy throughout. There is no light theme.
//

import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct PaneStride: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Marshal { Marshal() }

    func makeUIView(context: Context) -> UIView {
        let marshal = context.coordinator
        guard let containerView = marshal.mount() else {
            return UIView()
        }
        marshal.root = containerView
        marshal.pullCookies(containerView)
        marshal.open(url, into: containerView)
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

enum Palette {
    /// Screen background.
    static let background = Color(hex: 0x0B1A33)
    /// Panels.
    static let panel = Color(hex: 0x13274A)
    /// Recessed LCD windows and the tab bar.
    static let lcd = Color(hex: 0x07111F)
    /// Electricity, digits on displays, active states.
    static let yellow = Color(hex: 0xFFD23F)
    /// Peak hours, rising use, a bill that disagrees with the meter.
    static let red = Color(hex: 0xFF4B4B)
    /// Water and gas, secondary actions, section headers.
    static let blue = Color(hex: 0x4DA3FF)
    /// Main text.
    static let white = Color(hex: 0xEEF4FF)
    /// Unlit segments, panel borders, circuit traces.
    static let ghost = Color(hex: 0x1E3355)

    static let secondaryText = white.opacity(0.66)
    static let tertiaryText = white.opacity(0.45)

    static func utility(_ utility: Utility) -> Color {
        utility == .electricity ? yellow : blue
    }
}

enum TypeScale {
    /// Screen titles are written in lower case.
    static let screenTitle = Font.system(size: 30, weight: .bold)
    static let sectionHeader = Font.system(size: 12, weight: .semibold)
    static let reading = Font.system(size: 48, weight: .bold, design: .monospaced)
    static let money = Font.system(size: 36, weight: .bold).monospacedDigit()
    static let moneySmall = Font.system(size: 22, weight: .bold).monospacedDigit()
    static let body = Font.system(size: 16)
    static let bodyEmphasis = Font.system(size: 16, weight: .semibold)
    static let headline = Font.system(size: 20, weight: .bold)
    static let caption = Font.system(size: 13)
    static let captionEmphasis = Font.system(size: 13, weight: .semibold)
    static let button = Font.system(size: 17, weight: .bold)
    static let tab = Font.system(size: 10, weight: .semibold)

    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum Metrics {
    static let gutter: CGFloat = 20
    static let panelRadius: CGFloat = 14
    static let displayRadius: CGFloat = 6
    static let buttonRadius: CGFloat = 12
    static let buttonHeight: CGFloat = 56
    static let borderWidth: CGFloat = 2
    static let maxContentWidth: CGFloat = 640
}

enum Motion {
    static let digitDelay = 0.05
    static let barDelay = 0.03
    static let needle = Animation.interpolatingSpring(stiffness: 180, damping: 14)
    static let standard = Animation.easeInOut(duration: 0.25)
}

extension Utility {
    var symbol: String {
        switch self {
        case .electricity: return "bolt.fill"
        case .gas: return "flame.fill"
        case .water: return "drop.fill"
        }
    }
}

extension MeterKind {
    var symbol: String {
        switch self {
        case .electricitySingle: return "bolt.fill"
        case .electricityTwoRate: return "bolt.horizontal.fill"
        case .gas: return "flame.fill"
        case .waterCold: return "drop.fill"
        case .waterHot: return "drop.degreesign.fill"
        }
    }
}
