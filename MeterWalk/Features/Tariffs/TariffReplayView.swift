//
//  TariffReplayView.swift
//  MeterWalk
//
//  The key screen: real use over a period, priced on every tariff the user
//  entered, as columns and one plain sentence. Every assumption is written
//  under the result.
//

import SwiftUI

struct TariffReplayView: View {
    @EnvironmentObject private var store: AppStore
    let initialMeterID: UUID?

    @State private var meterID: UUID?
    @State private var window: ReplayWindow = .months12
    @State private var addingTariff = false
    @State private var expanded: UUID?

    private var meter: MeterItem? {
        store.state.meter(meterID ?? initialMeterID) ?? defaultMeter
    }

    /// The first meter with tariffs and use, else the first meter.
    private var defaultMeter: MeterItem? {
        store.state.meters.first { meter in
            !store.state.tariffs(for: meter.kind.tariffType).isEmpty
                && !ConsumptionEngine.dailySeries(meter: meter, readings: store.state.readings).isEmpty
        } ?? store.state.meters.first
    }

    var body: some View {
        ScreenScroll(spacing: 22) {
            ScreenTitle("tariff replay", subtitle: "Your real use, priced on every tariff you entered.")

            ListStateContainer {
                if let meter {
                    content(meter)
                } else {
                    EmptyStatePanel(symbol: "speedometer", title: "No meters", message: "Add a meter and take readings to replay tariffs on your use.")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingTariff) {
            TariffEditorView(tariff: nil, meterType: meter?.kind.tariffType)
        }
    }

    @ViewBuilder
    private func content(_ meter: MeterItem) -> some View {
        let series = ConsumptionEngine.dailySeries(meter: meter, readings: store.state.readings)
        let tariffs = store.state.tariffs(for: meter.kind.tariffType)
        let range = window.range(now: Date(), series: series)
        let result = TariffEngine.replay(meter: meter, series: series, tariffs: tariffs, from: range.from, to: range.to)

        VStack(alignment: .leading, spacing: 22) {
            if store.state.meters.count > 1 {
                meterPicker(selected: meter)
            }
            SegmentPicker(options: ReplayWindow.allCases, selection: $window) { $0.title }

            if tariffs.isEmpty {
                EmptyStatePanel(
                    symbol: "tag.fill",
                    title: "No \(meter.kind.tariffType.title.lowercased()) tariffs",
                    message: "Add your current \(meter.kind.tariffType.title.lowercased()) tariff and any you want to compare. The replay prices your real use on each.",
                    actionTitle: "Add a Tariff"
                ) { addingTariff = true }
            } else if series.isEmpty {
                EmptyStatePanel(
                    symbol: "hourglass",
                    title: "More readings needed",
                    message: "Two readings of \(meter.name) a few weeks apart give the use to replay. Two months of readings make it worth reading."
                )
            } else {
                headline(result, meter: meter)
                if !result.costs.isEmpty {
                    TariffColumns(result: result, money: store.money)
                }
                notes(result, meter: meter)
                if !meter.kind.isTwoRate && tariffs.contains(where: { $0.structure == .twoRate }) {
                    NightShareControl(meter: meter)
                }
                useSummary(result, meter: meter)
                breakdown(result, meter: meter)
                Button("Add a Tariff to Compare") { addingTariff = true }
                    .buttonStyle(.secondary)
            }
        }
    }

    private func meterPicker(selected: MeterItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.state.meters) { meter in
                    let active = meter.id == selected.id
                    Button {
                        withAnimation(Motion.standard) { meterID = meter.id }
                    } label: {
                        Label(meter.name, systemImage: meter.kind.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(active ? Palette.background : Palette.secondaryText)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Capsule().fill(active ? Palette.utility(meter.utility) : Palette.panel))
                            .overlay(Capsule().strokeBorder(active ? Color.clear : Palette.ghost, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Headline

    private func headline(_ result: ReplayResult, meter: MeterItem) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                if let current = result.current {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You paid")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.secondaryText)
                        Text(store.money.total(current.total))
                            .font(TypeScale.money)
                            .foregroundStyle(Palette.white)
                    }
                }
                Text(ReplayNarrative.sentence(result: result, window: window, money: store.money.total))
                    .font(TypeScale.bodyEmphasis)
                    .foregroundStyle(Palette.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let alternative = result.cheapestAlternative, let current = result.current, alternative.total < current.total {
                    HStack(spacing: 8) {
                        Text("Difference")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                        Text(store.money.total(current.total - alternative.total))
                            .font(TypeScale.moneySmall)
                            .foregroundStyle(Palette.yellow)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func notes(_ result: ReplayResult, meter: MeterItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let share = result.usesNightShareAssumption {
                AssumptionNote(text: ReplayNarrative.assumptionNote(share: share), symbol: "moon.fill", color: Palette.blue)
            }
            if result.current != nil {
                AssumptionNote(text: ReplayNarrative.calculatedNote)
            }
            if let coverage = ReplayNarrative.coverageNote(result: result) {
                AssumptionNote(text: coverage, symbol: "calendar")
            }
            if result.hasProratedTiers {
                AssumptionNote(text: ReplayNarrative.proratedNote, symbol: "stairs")
            }
            if result.costs.contains(where: { $0.exitFee > 0 }), let current = result.current {
                AssumptionNote(text: "Other tariffs include the exit fee of \(store.money.total(current.tariff.exitFee)) for leaving \(current.tariff.displayName).", symbol: "door.left.hand.open")
            }
            ForEach(result.costs.filter { !$0.isAvailable }) { cost in
                AssumptionNote(text: "\(cost.tariff.displayName): \(cost.unavailableReason ?? "")", symbol: "exclamationmark.circle", color: Palette.tertiaryText)
            }
        }
    }

    // MARK: Use

    private func useSummary(_ result: ReplayResult, meter: MeterItem) -> some View {
        TitledSection(title: "Use replayed") {
            Panel(padding: 14) {
                VStack(spacing: 8) {
                    KeyValueRow(key: "Days with readings", value: "\(result.coveredDays)", mono: true)
                    KeyValueRow(key: "Total use", value: "\(NumberText.use(result.totalUse)) \(meter.unit)", mono: true)
                    if let day = result.dayUse, let night = result.nightUse {
                        KeyValueRow(key: "Day", value: "\(NumberText.use(day)) \(meter.unit)", mono: true)
                        KeyValueRow(key: "Night", value: "\(NumberText.use(night)) \(meter.unit)", valueColor: Palette.blue, mono: true)
                    }
                    KeyValueRow(key: "Period", value: "\(DateText.short(result.from)) – \(DateText.short(ConsumptionEngine.addDays(-1, to: result.to)))")
                }
            }
        }
    }

    // MARK: Breakdown

    private func breakdown(_ result: ReplayResult, meter: MeterItem) -> some View {
        TitledSection(title: "How each total is made") {
            VStack(spacing: 10) {
                ForEach(result.costs) { cost in
                    let open = expanded == cost.id
                    Panel(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation(Motion.standard) { expanded = open ? nil : cost.id }
                            } label: {
                                HStack {
                                    Text(cost.tariff.displayName)
                                        .font(TypeScale.bodyEmphasis)
                                        .foregroundStyle(Palette.white)
                                    if cost.isCurrent { Badge(text: "Current", color: Palette.yellow, filled: true) }
                                    Spacer()
                                    Text(cost.isAvailable ? store.money.total(cost.total) : "—")
                                        .font(TypeScale.mono(16))
                                        .foregroundStyle(Palette.white)
                                    Image(systemName: open ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Palette.tertiaryText)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if open {
                                Divider2()
                                line("Standing charge", detail: "\(result.coveredDays) days × \(store.money.rate(cost.tariff.standingChargePerDay))", amount: cost.standing)
                                ForEach(cost.energyLines) { item in
                                    line(item.label, detail: "\(NumberText.use(item.quantity)) × \(store.money.rate(item.rate))", amount: item.amount)
                                }
                                if cost.exitFee > 0 {
                                    line("Exit fee to switch", detail: "from your current tariff", amount: cost.exitFee)
                                }
                                if let reason = cost.unavailableReason {
                                    AssumptionNote(text: reason, symbol: "exclamationmark.circle")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func line(_ title: String, detail: String, amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.white)
                Text(detail)
                    .font(TypeScale.mono(12, weight: .regular))
                    .foregroundStyle(Palette.tertiaryText)
            }
            Spacer()
            Text(store.money.exact(amount))
                .font(TypeScale.mono(14, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
        }
    }
}

// MARK: - Columns

/// One column per tariff, growing from the bottom one after another. The
/// cheapest is lit yellow; the current tariff is outlined.
struct TariffColumns: View {
    let result: ReplayResult
    let money: MoneyText

    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var priced: [TariffCost] { result.costs.filter(\.isAvailable) }
    private var maxTotal: Double { max(priced.map(\.total).max() ?? 1, 0.01) }

    var body: some View {
        Panel(padding: 14) {
            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(priced.enumerated()), id: \.element.id) { index, cost in
                        column(cost, index: index)
                    }
                }
                .frame(height: 190)
                Rectangle().fill(Palette.ghost).frame(height: 1.5)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(priced) { cost in
                        VStack(spacing: 3) {
                            Text(cost.tariff.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            if cost.isCurrent {
                                Text("current")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Palette.yellow)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onAppear {
            if reduceMotion { grown = true } else { DispatchQueue.main.async { grown = true } }
        }
    }

    private func column(_ cost: TariffCost, index: Int) -> some View {
        let cheapest = cost.id == result.cheapest?.id
        let fraction = cost.total / maxTotal
        return VStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(money.total(cost.total))
                .font(TypeScale.mono(12, weight: .semibold))
                .foregroundStyle(cheapest ? Palette.yellow : Palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .opacity(grown ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.35 + Double(index) * Motion.barDelay), value: grown)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(cheapest ? Palette.yellow : Palette.blue.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(cost.isCurrent ? Palette.white : Color.clear, lineWidth: 2)
                )
                .frame(height: max(4, CGFloat(fraction) * 150))
                .scaleEffect(x: 1, y: grown ? 1 : 0.001, anchor: .bottom)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.55).delay(Double(index) * Motion.barDelay), value: grown)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(cost.tariff.displayName))
        .accessibilityValue(Text("\(money.total(cost.total))\(cost.isCurrent ? ", current" : "")\(cheapest ? ", cheapest" : "")"))
    }
}

// MARK: - Night share

/// A single-rate meter cannot tell day use from night use. The user sets the
/// share themselves; the app never guesses it.
struct NightShareControl: View {
    @EnvironmentObject private var store: AppStore
    let meter: MeterItem
    @State private var share: Double = 0.3

    var body: some View {
        TitledSection(title: "Night share") {
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(meter.name) has one counter, so it cannot show how much you use at night. Two-rate tariffs are only priced once you set the share you believe is used at night.")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let current = meter.nightShareAssumption {
                        HStack(alignment: .firstTextBaseline) {
                            Text(NumberText.percent(current * 100))
                                .font(TypeScale.money)
                                .foregroundStyle(Palette.blue)
                            Text("of your use at night, as you set it")
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                    Slider(value: $share, in: 0...0.8, step: 0.05)
                        .tint(Palette.blue)
                        .accessibilityLabel("Night share")
                        .accessibilityValue(NumberText.percent(share * 100))
                    HStack(spacing: 12) {
                        if meter.nightShareAssumption != share {
                            Button(meter.nightShareAssumption == nil ? "Use \(NumberText.percent(share * 100))" : "Change to \(NumberText.percent(share * 100))") {
                                store.setNightShare(share, for: meter.id)
                            }
                            .buttonStyle(.secondary)
                        } else {
                            Text("Move the slider to change it.")
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.tertiaryText)
                            Spacer()
                        }
                        if meter.nightShareAssumption != nil {
                            Button("Clear") { store.setNightShare(nil, for: meter.id) }
                                .buttonStyle(InlineButtonStyle(color: Palette.red))
                        }
                    }
                }
            }
        }
        .onAppear { share = meter.nightShareAssumption ?? 0.3 }
    }
}
