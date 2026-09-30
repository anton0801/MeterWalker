//
//  TariffsView.swift
//  MeterWalk
//
//  The user's own tariff and any they want to compare, with Tariff Replay
//  at the top.
//

import SwiftUI

struct TariffsView: View {
    @EnvironmentObject private var store: AppStore
    var isRoot = true
    @State private var adding = false

    var body: some View {
        ScreenScroll(spacing: 22) {
            ScreenTitle(text: "tariffs", subtitle: "Your tariff and the ones you might switch to.") {
                IconButton(symbol: "plus", label: "Add tariff", color: Palette.yellow) { adding = true }
            }

            ListStateContainer {
                VStack(alignment: .leading, spacing: 22) {
                    replayTeaser
                    if store.state.tariffs.isEmpty {
                        EmptyStatePanel(
                            symbol: "tag.fill",
                            title: "No tariffs yet",
                            message: "Add the tariff you are on now, with its standing charge and unit rates, then any you are thinking of switching to. Nothing is filled in for you.",
                            actionTitle: "Add a Tariff"
                        ) { adding = true }
                    } else {
                        ForEach(TariffMeterType.allCases) { type in
                            let tariffs = store.state.tariffs(for: type)
                                .sorted { lhs, rhs in
                                    lhs.isCurrent != rhs.isCurrent ? lhs.isCurrent : lhs.displayName < rhs.displayName
                                }
                            if !tariffs.isEmpty {
                                TitledSection(title: type.title, trailing: "\(tariffs.count)") {
                                    VStack(spacing: 10) {
                                        ForEach(tariffs) { tariff in
                                            NavigationLink(value: Route.tariff(tariff.id)) {
                                                TariffRow(tariff: tariff)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(isRoot ? "" : "Tariffs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isRoot ? .hidden : .visible, for: .navigationBar)
        .sheet(isPresented: $adding) {
            TariffEditorView(tariff: nil)
        }
    }

    @ViewBuilder
    private var replayTeaser: some View {
        if !store.state.meters.isEmpty {
            NavigationLink(value: Route.tariffReplay(nil)) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous).fill(Palette.panel)
                    CircuitTraces(seed: 5, density: 1.2)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader("Tariff replay")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.tertiaryText)
                        }
                        Text(teaserText)
                            .font(TypeScale.bodyEmphasis)
                            .foregroundStyle(Palette.white)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
                        .strokeBorder(Palette.yellow.opacity(0.6), lineWidth: Metrics.borderWidth)
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// The replay sentence for the first meter that can be replayed.
    private var teaserText: String {
        for meter in store.state.meters {
            let tariffs = store.state.tariffs(for: meter.kind.tariffType)
            guard !tariffs.isEmpty else { continue }
            let series = ConsumptionEngine.dailySeries(meter: meter, readings: store.state.readings)
            guard !series.isEmpty else { continue }
            let range = ReplayWindow.months12.range(now: Date(), series: series)
            let result = TariffEngine.replay(meter: meter, series: series, tariffs: tariffs, from: range.from, to: range.to)
            return ReplayNarrative.sentence(result: result, window: .months12, money: store.money.total)
        }
        return "Your real use, priced on every tariff you enter — standing charge, day and night rates and tiers included."
    }
}

struct TariffRow: View {
    @EnvironmentObject private var store: AppStore
    let tariff: Tariff

    var body: some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(tariff.displayName)
                        .font(TypeScale.bodyEmphasis)
                        .foregroundStyle(Palette.white)
                        .lineLimit(1)
                    if tariff.isCurrent {
                        Badge(text: "Current", color: Palette.yellow, filled: true)
                    }
                    Spacer()
                    Badge(text: tariff.structure.title, color: Palette.blue)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryText)
                }
                Text(TariffSummary.rates(tariff, money: store.money))
                    .font(TypeScale.mono(13, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(2)
                if let ends = tariff.endsOn {
                    Text("\(tariff.supplier.isEmpty ? "" : tariff.supplier + " · ")ends \(DateText.short(ends))")
                        .font(TypeScale.caption)
                        .foregroundStyle(ends < Date() ? Palette.red : Palette.tertiaryText)
                } else if !tariff.supplier.isEmpty {
                    Text(tariff.supplier)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum TariffSummary {
    static func rates(_ tariff: Tariff, money: MoneyText) -> String {
        let unit = tariff.meterType.unit
        var parts: [String] = []
        switch tariff.structure {
        case .flat:
            parts.append("\(money.rate(tariff.unitRate))/\(unit)")
        case .twoRate:
            parts.append("day \(money.rate(tariff.dayRate))")
            parts.append("night \(money.rate(tariff.nightRate))")
        case .tiered:
            let tiers = tariff.sortedTiers
            parts.append("\(tiers.count) \(tiers.count == 1 ? "step" : "steps") from \(money.rate(tiers.map(\.rate).min() ?? 0))")
        }
        parts.append("\(money.rate(tariff.standingChargePerDay))/day")
        return parts.joined(separator: " · ")
    }
}
