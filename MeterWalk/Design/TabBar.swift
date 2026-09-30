//
//  TabBar.swift
//  MeterWalk
//
//  Home · Meters · [camera] · Tariffs · Bills. The camera button sits in the
//  middle, raised above the bar, and opens the reading scanner.
//

import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home, meters, tariffs, bills

    var title: String {
        switch self {
        case .home: return "Home"
        case .meters: return "Meters"
        case .tariffs: return "Tariffs"
        case .bills: return "Bills"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .meters: return "speedometer"
        case .tariffs: return "tag.fill"
        case .bills: return "doc.text.fill"
        }
    }
}

struct MeterTabBar: View {
    @Binding var selection: AppTab
    /// Height of the bar above the home indicator.
    let contentHeight: CGFloat
    let onScan: () -> Void

    static let totalHeight: CGFloat = 88
    static let cameraSize: CGFloat = 64
    static let cameraRaise: CGFloat = 12

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            item(.home)
            item(.meters)
            scanSlot
            item(.tariffs)
            item(.bills)
        }
        .frame(height: contentHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(
            Palette.lcd
                .overlay(alignment: .top) { Rectangle().fill(Palette.ghost).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func item(_ tab: AppTab) -> some View {
        let active = selection == tab
        return Button {
            if selection != tab {
                selection = tab
                UISelectionFeedbackGenerator().selectionChanged()
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(height: 22)
                Text(tab.title)
                    .font(TypeScale.tab)
                Circle()
                    .fill(active ? Palette.yellow : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(active ? Palette.yellow : Palette.white.opacity(0.45))
            .padding(.top, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }

    private var scanSlot: some View {
        VStack(spacing: 4) {
            Button(action: onScan) {
                ZStack {
                    Circle()
                        .fill(Palette.lcd)
                        .frame(width: MeterTabBar.cameraSize + 10, height: MeterTabBar.cameraSize + 10)
                    Circle()
                        .fill(Palette.yellow)
                        .frame(width: MeterTabBar.cameraSize, height: MeterTabBar.cameraSize)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Palette.background)
                }
            }
            .buttonStyle(CameraButtonStyle())
            // Raised so its top clears the bar by 12pt.
            .offset(y: -(MeterTabBar.cameraSize / 2 + MeterTabBar.cameraRaise) + 10)
            .frame(height: 30, alignment: .top)
            .accessibilityLabel("Scan a meter")
            .accessibilityHint("Opens the camera to take a reading")

            Text("Scan")
                .font(TypeScale.tab)
                .foregroundStyle(Palette.white.opacity(0.45))
                .padding(.top, 2)
                .accessibilityHidden(true)
        }
        .padding(.top, 9)
        .frame(maxWidth: .infinity)
    }
}

private struct CameraButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
