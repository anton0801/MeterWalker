//
//  Components.swift
//  MeterWalk
//
//  Titles, headers, badges and the loading / empty / error states every list
//  shares.
//

import SwiftUI

// MARK: - Screen scaffold

/// Navy scrolling screen with the standard gutter and a readable max width.
struct ScreenScroll<Content: View>: View {
    var spacing: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: Metrics.maxContentWidth, alignment: .leading)
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background.ignoresSafeArea())
    }
}

/// Lower-case 30pt screen title, with optional trailing controls.
struct ScreenTitle<Trailing: View>: View {
    let text: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ScreenTitleCase.apply(text))
                    .font(TypeScale.screenTitle)
                    .tracking(-0.5)
                    .foregroundStyle(Palette.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// Screen titles are lower case, except units that mean something else
/// in lower case.
enum ScreenTitleCase {
    private static let keep = ["kWh", "m³"]

    static func apply(_ text: String) -> String {
        var result = text.lowercased()
        for unit in keep {
            result = result.replacingOccurrences(of: unit.lowercased(), with: unit)
        }
        return result
    }
}

extension ScreenTitle where Trailing == EmptyView {
    init(_ text: String, subtitle: String? = nil) {
        self.text = text
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// Upper-case 12pt blue header with +2 tracking.
struct SectionHeader: View {
    let text: String
    var trailing: String? = nil

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(TypeScale.sectionHeader)
                .tracking(2)
                .foregroundStyle(Palette.blue)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
    }
}

struct TitledSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            SectionHeader(title, trailing: trailing)
            content
        }
    }
}

// MARK: - Small pieces

struct Badge: View {
    let text: String
    var color: Color = Palette.blue
    var filled = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(filled ? Palette.background : color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(filled ? color : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(color, lineWidth: filled ? 0 : 1.5)
            )
    }
}

/// A labelled note that explains an assumption or a limit in a calculation.
struct AssumptionNote: View {
    let text: String
    var symbol = "info.circle"
    var color: Color = Palette.secondaryText

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(TypeScale.caption)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color = Palette.white
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(TypeScale.body)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? TypeScale.mono(16, weight: .semibold) : TypeScale.bodyEmphasis)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct Divider2: View {
    var body: some View {
        Rectangle().fill(Palette.ghost).frame(height: 1)
    }
}

/// Chevron row inside a panel.
struct NavigationRowLabel: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var tint: Color = Palette.white

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(title)
                .font(TypeScale.body)
                .foregroundStyle(Palette.white)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - List states

/// Shown while the document loads: unlit LCD panels.
struct LoadingPanels: View {
    var count = 3
    @State private var dim = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(Palette.ghost).frame(width: 120, height: 12)
                        RecessedDisplay {
                            Text("88888.8")
                                .font(TypeScale.mono(36))
                                .foregroundStyle(Palette.ghost)
                        }
                    }
                }
            }
        }
        .opacity(dim ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// Empty list: circuit traces behind a short explanation and one action.
struct EmptyStatePanel: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.yellow)
                .frame(width: 52, height: 52)
                .background(RecessedShape(radius: 10))
            Text(title)
                .font(TypeScale.headline)
                .foregroundStyle(Palette.white)
            Text(message)
                .font(TypeScale.body)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous).fill(Palette.panel)
                CircuitTraces(seed: SeededRandom.stableSeed(title))
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous))
                    .opacity(0.9)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
                .strokeBorder(Palette.ghost, lineWidth: Metrics.borderWidth)
        )
    }
}

struct ErrorStatePanel: View {
    let title: String
    let message: String
    var retryTitle = "Try Again"
    var retry: (() -> Void)? = nil

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.red)
                    Text(title)
                        .font(TypeScale.bodyEmphasis)
                        .foregroundStyle(Palette.white)
                }
                Text(message)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button(retryTitle, action: retry)
                        .buttonStyle(.secondary)
                }
            }
        }
    }
}

/// Wraps a list body with the store's load state so every list shows the
/// same loading and error states.
struct ListStateContainer<Content: View>: View {
    @EnvironmentObject private var store: AppStore
    var loadingCount = 3
    @ViewBuilder var content: Content

    var body: some View {
        switch store.loadState {
        case .loading:
            LoadingPanels(count: loadingCount)
        case .failed(let message):
            ErrorStatePanel(title: "Your data could not be opened", message: message) {
                Task { await store.load() }
            }
        case .loaded:
            content
        }
    }
}

// MARK: - Banner

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.red)
            Text(message)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.lcd))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.red, lineWidth: 1.5))
        .padding(.horizontal, Metrics.gutter)
    }
}
