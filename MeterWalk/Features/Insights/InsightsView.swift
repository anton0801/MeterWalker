//
//  InsightsView.swift
//  MeterWalk
//
//  The two answers that matter most first: the cheapest tariff for the
//  user's real use, and any overbilling found. Then the supporting figures.
//

import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let report = InsightsEngine.report(state: store.state)
        ScreenScroll(spacing: 24) {
            ScreenTitle("insights", subtitle: "From your own readings, tariffs and bills.")

            ListStateContainer {
                if !report.hasDailyRate {
                    EmptyStatePanel(
                        symbol: "hourglass",
                        title: "More Readings Needed",
                        message: "Two months of readings are needed to see a daily rate. Take one photo of each meter a month."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        cheapest(report)
                        overbilled(report)
                        costPerDay(report)
                        changes(report)
                        estimatedBills(report)
                        monthly(report)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Cheapest

    @ViewBuilder
    private func cheapest(_ report: InsightsReport) -> some View {
        TitledSection(title: "Cheapest tariff for your use") {
            if report.cheapest.isEmpty {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add your current tariff and at least one other to see which would have cost least for your real use.")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        NavigationLink(value: Route.tariffs) {
                            Text("Go to Tariffs")
                        }
                        .buttonStyle(InlineButtonStyle())
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(report.cheapest) { item in
                        NavigationLink(value: Route.tariffReplay(item.meter.id)) {
                            Panel {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label(item.meter.name, systemImage: item.meter.kind.symbol)
                                            .font(TypeScale.captionEmphasis)
                                            .foregroundStyle(Palette.secondaryText)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Palette.tertiaryText)
                                    }
                                    Text(item.cheapest.tariff.displayName)
                                        .font(TypeScale.headline)
                                        .foregroundStyle(Palette.yellow)
                                    Text(cheapestText(item))
                                        .font(TypeScale.body)
                                        .foregroundStyle(Palette.white)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let share = item.cheapest.nightShareAssumption {
                                        AssumptionNote(text: ReplayNarrative.assumptionNote(share: share))
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func cheapestText(_ item: CheapestTariffInsight) -> String {
        let money = store.money
        let days = item.result.coveredDays
        if let saving = item.saving, let current = item.current {
            return "\(money.total(item.cheapest.total)) for the \(days) days your readings cover, against \(money.total(current.total)) on \(current.tariff.displayName). \(money.total(saving)) less\(item.cheapest.exitFee > 0 ? ", exit fee included" : "")."
        }
        if item.current?.id == item.cheapest.id {
            return "Your current tariff was the cheapest for your use over the \(days) days your readings cover: \(money.total(item.cheapest.total))."
        }
        return "\(money.total(item.cheapest.total)) for the \(days) days your readings cover. Mark your current tariff to see the difference."
    }

    // MARK: Overbilled

    @ViewBuilder
    private func overbilled(_ report: InsightsReport) -> some View {
        TitledSection(title: "Overbilled amount found") {
            if report.overbilled.isEmpty {
                Panel {
                    Text(report.checkedBillCount == 0
                         ? "Add a bill with the readings printed on it to check it against your photos."
                         : "\(report.checkedBillCount) \(report.checkedBillCount == 1 ? "bill" : "bills") checked. None charged for more than your meter shows.")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        if report.overbilledMoney > 0 {
                            Text(store.money.total(report.overbilledMoney))
                                .font(TypeScale.money)
                                .foregroundStyle(Palette.red)
                        }
                        Text("Charged for use your meter photos do not show, across \(report.overbilled.count) \(report.overbilled.count == 1 ? "bill" : "bills").")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.white)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(report.overbilled) { item in
                            NavigationLink(value: Route.bill(item.bill.id)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.bill.supplier.isEmpty ? item.meter.name : item.bill.supplier)
                                            .font(TypeScale.bodyEmphasis)
                                            .foregroundStyle(Palette.white)
                                        Text("\(DateText.short(item.bill.periodFrom)) – \(DateText.short(item.bill.periodTo))")
                                            .font(TypeScale.caption)
                                            .foregroundStyle(Palette.tertiaryText)
                                    }
                                    Spacer()
                                    Text("+\(NumberText.use(item.result.excessUnits ?? 0)) \(item.meter.unit)")
                                        .font(TypeScale.mono(15, weight: .semibold))
                                        .foregroundStyle(Palette.red)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Palette.tertiaryText)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: Cost per day

    @ViewBuilder
    private func costPerDay(_ report: InsightsReport) -> some View {
        if !report.costPerDay.isEmpty {
            TitledSection(title: "Cost per day") {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.costPerDay) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Label(item.meter.name, systemImage: item.meter.kind.symbol)
                                    .font(TypeScale.body)
                                    .foregroundStyle(Palette.white)
                                Spacer()
                                Text(store.money.exact(item.perDay))
                                    .font(TypeScale.mono(17))
                                    .foregroundStyle(Palette.white)
                            }
                        }
                        AssumptionNote(text: "On your current tariffs, standing charge included, over the last 3 months your readings cover.")
                    }
                }
            }
        }
    }

    // MARK: Change

    @ViewBuilder
    private func changes(_ report: InsightsReport) -> some View {
        if !report.changes.isEmpty {
            TitledSection(title: "Change vs last year") {
                VStack(spacing: 12) {
                    ForEach(report.changes) { item in
                        Panel(padding: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(item.meter.name, systemImage: item.meter.kind.symbol)
                                    .font(TypeScale.captionEmphasis)
                                    .foregroundStyle(Palette.secondaryText)
                                ComparisonLine(comparison: item.comparison, unit: item.meter.unit)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Estimated bills

    private func estimatedBills(_ report: InsightsReport) -> some View {
        TitledSection(title: "Estimated bills received") {
            Panel {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(report.estimatedBillCount)")
                        .font(TypeScale.money)
                        .foregroundStyle(report.estimatedBillCount > 0 ? Palette.blue : Palette.white)
                    Text(report.estimatedBillCount == 1
                         ? "bill was worked out from an estimate, not a real reading."
                         : "bills were worked out from an estimate, not a real reading.")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Monthly

    @ViewBuilder
    private func monthly(_ report: InsightsReport) -> some View {
        if !report.monthly.isEmpty {
            TitledSection(title: "Daily use by month") {
                VStack(spacing: 12) {
                    ForEach(report.monthly) { item in
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(item.meter.name, systemImage: item.meter.kind.symbol)
                                    .font(TypeScale.captionEmphasis)
                                    .foregroundStyle(Palette.secondaryText)
                                MonthBarsChart(months: item.months, unit: item.meter.unit, height: 90, thisYearColor: Palette.utility(item.meter.utility))
                            }
                        }
                    }
                }
            }
        }
    }
}
