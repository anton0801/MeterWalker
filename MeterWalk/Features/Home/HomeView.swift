//
//  HomeView.swift
//  MeterWalk
//
//  Top: this month's daily use against last year on the dial. Middle: twelve
//  months across the full width. Below: an LCD panel for every meter.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @AppStorage("home.selectedMeterID") private var selectedMeterIDString = ""

    private var selectedMeter: MeterItem? {
        let meters = store.state.meters
        if let id = UUID(uuidString: selectedMeterIDString), let meter = meters.first(where: { $0.id == id }) {
            return meter
        }
        return meters.first { $0.utility == .electricity } ?? meters.first
    }

    var body: some View {
        ScreenScroll(spacing: 26) {
            ScreenTitle(text: "home", subtitle: DateText.full(Date())) {
                HStack(spacing: 10) {
                    NavigationLink(value: Route.insights) {
                        headerIcon("chart.bar.xaxis", label: "Insights")
                    }
                    NavigationLink(value: Route.settings) {
                        headerIcon("gearshape.fill", label: "Settings")
                    }
                }
                .buttonStyle(.plain)
            }

            ListStateContainer(loadingCount: 2) {
                if store.state.meters.isEmpty {
                    EmptyStatePanel(
                        symbol: "speedometer",
                        title: "No meters",
                        message: "Add the meters you read. Everything here is worked out from your own photos of them.",
                        actionTitle: "Add a Meter"
                    ) { router.show(.meters) }
                } else if let meter = selectedMeter {
                    content(meter)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func headerIcon(_ symbol: String, label: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.white)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Palette.panel))
            .overlay(Circle().strokeBorder(Palette.ghost, lineWidth: 2))
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private func content(_ meter: MeterItem) -> some View {
        let series = ConsumptionEngine.dailySeries(meter: meter, readings: store.state.readings)
        let comparison = ConsumptionEngine.yearComparison(series: series, now: Date())

        VStack(alignment: .leading, spacing: 26) {
            if store.state.meters.count > 1 {
                meterPicker(selected: meter)
            }

            gaugeSection(meter, series: series, comparison: comparison)
                .id(meter.id)

            if !series.isEmpty {
                TitledSection(title: "Last 12 months") {
                    MonthBarsChart(
                        months: ConsumptionEngine.twelveMonths(series: series, now: Date()),
                        unit: meter.unit,
                        height: 170,
                        thisYearColor: Palette.utility(meter.utility)
                    )
                    .id(meter.id)
                }
            }

            alerts

            TitledSection(title: "Meters") {
                VStack(spacing: 12) {
                    ForEach(store.state.meters) { item in
                        NavigationLink(value: Route.meter(item.id)) {
                            MeterSummaryPanel(meter: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Meter picker

    private func meterPicker(selected: MeterItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.state.meters) { meter in
                    let active = meter.id == selected.id
                    Button {
                        withAnimation(Motion.standard) { selectedMeterIDString = meter.id.uuidString }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: meter.kind.symbol)
                                .font(.system(size: 12, weight: .bold))
                            Text(meter.name)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(active ? Palette.background : Palette.secondaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(active ? Palette.utility(meter.utility) : Palette.panel))
                        .overlay(Capsule().strokeBorder(active ? Color.clear : Palette.ghost, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Gauge

    @ViewBuilder
    private func gaugeSection(_ meter: MeterItem, series: [Date: DayUse], comparison: YearComparison?) -> some View {
        TitledSection(title: "Daily use vs last year") {
            if let comparison {
                Panel(padding: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        ZStack {
                            CircuitTraces(seed: 29, density: 1.1)
                                .padding(-16)
                            UsageGauge(value: comparison.current, baseline: comparison.baseline)
                                .frame(maxWidth: 420)
                                .padding(.horizontal, 12)
                        }
                        .overlay(alignment: .bottom) {
                            HStack {
                                Text("0")
                                Spacer()
                                Text("2×")
                            }
                            .frame(maxWidth: 420)
                            .font(TypeScale.mono(11, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryText)
                        }
                        .clipped()

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(NumberText.rate(comparison.current))
                                .font(TypeScale.money)
                                .foregroundStyle(Palette.white)
                            Text("\(meter.unit) a day in \(DateText.month(comparison.month))")
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        ComparisonLine(comparison: comparison, unit: meter.unit)
                        if comparison.currentRough {
                            AssumptionNote(text: "Rough: this month comes from readings more than 45 days apart.", symbol: "exclamationmark.circle")
                        }
                    }
                }
            } else if let rate = ConsumptionEngine.latestDailyRate(meter: meter, readings: store.state.readings) {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        RecessedDisplay {
                            FittedLCD(text: String(format: "%.2f", rate.rate), maxSize: 44, color: Palette.utility(meter.utility), unit: "\(meter.unit)/day")
                        }
                        AssumptionNote(text: "The dial appears once there is a month of readings before this one to compare with.", symbol: "hourglass")
                    }
                }
            } else {
                moreReadingsNeeded(meter)
            }
        }
    }

    private func moreReadingsNeeded(_ meter: MeterItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EmptyStatePanel(
                symbol: "speedometer",
                title: "More readings needed",
                message: nextStepText(meter),
                actionTitle: "Take a Reading"
            ) { router.openScanner(meterID: meter.id) }
        }
    }

    private func nextStepText(_ meter: MeterItem) -> String {
        let count = meter.registers.map { ConsumptionEngine.countedReadings(store.state.readings, meterID: meter.id, register: $0).count }.min() ?? 0
        if count == 0 {
            return "Photograph \(meter.name) to start. Its daily use appears after the second reading."
        }
        return "You have your first reading of \(meter.name). One more, a few weeks from now, gives the first daily rate; two months of readings show the monthly picture."
    }

    // MARK: Alerts

    @ViewBuilder
    private var alerts: some View {
        let overbilled = overbilledBills
        if !overbilled.isEmpty {
            TitledSection(title: "Bill check") {
                VStack(spacing: 10) {
                    ForEach(overbilled, id: \.bill.id) { item in
                        NavigationLink(value: Route.bill(item.bill.id)) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Palette.red)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(overbilledTitle(item))
                                        .font(TypeScale.bodyEmphasis)
                                        .foregroundStyle(Palette.white)
                                        .multilineTextAlignment(.leading)
                                    Text("\(item.bill.supplier.isEmpty ? "Bill" : item.bill.supplier), \(DateText.short(item.bill.periodFrom)) – \(DateText.short(item.bill.periodTo))")
                                        .font(TypeScale.caption)
                                        .foregroundStyle(Palette.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.tertiaryText)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: Metrics.panelRadius).fill(Palette.panel))
                            .overlay(RoundedRectangle(cornerRadius: Metrics.panelRadius).strokeBorder(Palette.red.opacity(0.7), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var overbilledBills: [OverbilledBill] {
        store.state.bills.compactMap { bill in
            guard let meter = store.state.meter(bill.meterID) else { return nil }
            let result = BillCheckEngine.check(bill: bill, meter: meter, readings: store.state.readings, currentTariff: store.state.currentTariff(for: meter.kind.tariffType))
            return result.status == .overbilled ? OverbilledBill(bill: bill, meter: meter, result: result) : nil
        }
    }

    private func overbilledTitle(_ item: OverbilledBill) -> String {
        let units = NumberText.use(item.result.excessUnits ?? 0)
        if let money = item.result.excessMoney {
            return "Billed for \(units) \(item.meter.unit) you have not used, about \(store.money.total(money))"
        }
        return "Billed for \(units) \(item.meter.unit) you have not used"
    }
}
