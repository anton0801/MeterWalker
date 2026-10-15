//
//  MeterDetailView.swift
//  MeterWalk
//
//  One meter: its latest reading, daily use, the monthly picture and every
//  reading with its photo.
//

import SwiftUI

struct MeterDetailView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    let meterID: UUID

    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var historyRegister: Register = .total
    @State private var typing: Register?
    @State private var choosingTypedRegister = false

    var body: some View {
        Group {
            if let meter = store.state.meter(meterID) {
                content(meter)
            } else {
                ScreenScroll {
                    EmptyStatePanel(symbol: "speedometer", title: "Meter removed", message: "This meter is no longer in the app.")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ meter: MeterItem) -> some View {
        let series = ConsumptionEngine.dailySeries(meter: meter, readings: store.state.readings)
        let intervals = ConsumptionEngine.intervals(meter: meter, readings: store.state.readings)
        return ScreenScroll(spacing: 22) {
            ScreenTitle(text: meter.name, subtitle: meter.kind.title) {
                EmptyView()
            }

            MeterSummaryPanel(meter: meter, showsChevron: false)

            VStack(spacing: 12) {
                Button("Take a Reading") { router.openScanner(meterID: meter.id) }
                    .buttonStyle(.primary)
                Button("Type a Past Reading") {
                    if meter.kind.isTwoRate {
                        choosingTypedRegister = true
                    } else {
                        typing = .total
                    }
                }
                .buttonStyle(.secondary)
            }

            rateSection(meter, series: series, intervals: intervals)

            if !series.isEmpty {
                TitledSection(title: "Last 12 months") {
                    Panel {
                        MonthBarsChart(
                            months: ConsumptionEngine.twelveMonths(series: series, now: Date()),
                            unit: meter.unit,
                            height: 120,
                            thisYearColor: Palette.utility(meter.utility)
                        )
                    }
                }
            }

            history(meter, intervals: intervals)
            info(meter)

            Button("Delete Meter") { confirmingDelete = true }
                .buttonStyle(.destructive)
                .padding(.top, 8)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
                    .foregroundStyle(Palette.yellow)
            }
        }
        .sheet(isPresented: $editing) {
            MeterEditorView(meter: meter)
        }
        .confirmationDialog("Which register?", isPresented: $choosingTypedRegister, titleVisibility: .visible) {
            ForEach(meter.registers) { register in
                Button("\(register.title) \(register.meterLabel)") { typing = register }
            }
        }
        .fullScreenCover(item: $typing) { register in
            ReviewReadingView(
                meter: meter,
                capture: .init(meterID: meter.id, register: register, photo: nil, photoDate: nil, recognized: nil, recognitionFailed: false),
                onBack: { typing = nil },
                onClose: { typing = nil },
                onSaved: { _ in typing = nil }
            )
            .background(Palette.background.ignoresSafeArea())
            .environmentObject(store)
        }
        .alert("Delete \(meter.name)?", isPresented: $confirmingDelete) {
            Button("Delete Meter and Readings", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    store.deleteMeter(meter.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every reading and meter photo for it is deleted from this iPhone. Bills stay, without the link to this meter.")
        }
        .onAppear {
            if !meter.registers.contains(historyRegister) { historyRegister = meter.registers[0] }
        }
    }

    // MARK: Rate

    @ViewBuilder
    private func rateSection(_ meter: MeterItem, series: [Date: DayUse], intervals: [Register: [UseInterval]]) -> some View {
        TitledSection(title: "Daily use") {
            if let latest = ConsumptionEngine.latestDailyRate(meter: meter, readings: store.state.readings) {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(NumberText.rate(latest.rate))
                                .font(TypeScale.money)
                                .foregroundStyle(Palette.white)
                            Text("\(meter.unit) a day")
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Text("Since \(DateText.short(latest.since)), over \(DateText.days(latest.days)).")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.secondaryText)
                        if meter.kind.isTwoRate,
                           let day = intervals[.day]?.last, let night = intervals[.night]?.last {
                            let total = day.dailyRate + night.dailyRate
                            HStack(spacing: 16) {
                                KeyValueRow(key: "Day", value: NumberText.rate(day.dailyRate), mono: true)
                                KeyValueRow(key: "Night", value: NumberText.rate(night.dailyRate), mono: true)
                            }
                            if total > 0 {
                                Text("Night is \(NumberText.percent(night.dailyRate / total * 100)) of your use.")
                                    .font(TypeScale.caption)
                                    .foregroundStyle(Palette.secondaryText)
                            }
                        }
                        if latest.rough {
                            AssumptionNote(text: "Rough: the last readings are more than 45 days apart.", symbol: "exclamationmark.circle")
                        }
                        if let comparison = ConsumptionEngine.yearComparison(series: series, now: Date()) {
                            Divider2()
                            ComparisonLine(comparison: comparison, unit: meter.unit)
                        }
                    }
                }
            } else {
                Panel {
                    AssumptionNote(
                        text: "More readings needed. Two readings a few weeks apart give the first daily rate.",
                        symbol: "hourglass"
                    )
                }
            }
        }
    }

    // MARK: History

    @ViewBuilder
    private func history(_ meter: MeterItem, intervals: [Register: [UseInterval]]) -> some View {
        let register = meter.registers.contains(historyRegister) ? historyRegister : meter.registers[0]
        let readings = store.state.readings(for: meter.id, register: register).sorted { $0.date > $1.date }
        let byEnd = Dictionary((intervals[register] ?? []).map { ($0.endReadingID, $0) }, uniquingKeysWith: { a, _ in a })

        TitledSection(title: "Readings", trailing: readings.isEmpty ? nil : "\(readings.count)") {
            if meter.kind.isTwoRate {
                SegmentPicker(options: meter.registers, selection: $historyRegister) { "\($0.title) \($0.meterLabel)" }
            }
            if readings.isEmpty {
                EmptyStatePanel(
                    symbol: "camera.viewfinder",
                    title: "No readings yet",
                    message: "Photograph the meter to record its first reading. The photo is kept as proof."
                )
            } else {
                Panel(padding: 12) {
                    VStack(spacing: 0) {
                        ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                            NavigationLink(value: Route.reading(reading.id)) {
                                ReadingRow(meter: meter, reading: reading, interval: byEnd[reading.id])
                            }
                            .buttonStyle(.plain)
                            if index < readings.count - 1 { Divider2() }
                        }
                    }
                }
            }
        }
    }

    // MARK: Info

    private func info(_ meter: MeterItem) -> some View {
        TitledSection(title: "About this meter") {
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    KeyValueRow(key: "Type", value: meter.kind.title)
                    KeyValueRow(key: "Dial", value: meter.ghostText, mono: true)
                    KeyValueRow(key: "Unit", value: meter.unit)
                    if !meter.serialNumber.isEmpty { KeyValueRow(key: "Serial Number", value: meter.serialNumber, mono: true) }
                    if !meter.location.isEmpty { KeyValueRow(key: "Location", value: meter.location) }
                    if !meter.supplier.isEmpty { KeyValueRow(key: "Supplier", value: meter.supplier) }
                    let bills = store.state.bills(for: meter.id).count
                    KeyValueRow(key: "Bills", value: bills == 0 ? "None" : "\(bills)")
                    if !meter.notes.isEmpty {
                        Divider2()
                        Text(meter.notes)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    if meter.photoFile != nil {
                        PhotoPanel(fileName: meter.photoFile, caption: "Meter photo", height: 160)
                    }
                }
            }
        }
    }
}

/// "12% more than last September" with the baseline labelled.
struct ComparisonLine: View {
    let comparison: YearComparison
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let change = comparison.changePercent {
                let up = change > 0.5
                HStack(spacing: 6) {
                    Image(systemName: up ? "arrow.up.right" : (change < -0.5 ? "arrow.down.right" : "equal"))
                        .font(.system(size: 13, weight: .bold))
                    Text("\(NumberText.signedPercent(change)) \(against)")
                        .font(TypeScale.bodyEmphasis)
                }
                .foregroundStyle(up ? Palette.red : Palette.white)
            }
            Text("\(DateText.month(comparison.month)): \(NumberText.rate(comparison.current)) \(unit)/day. \(baselineText)")
                .font(TypeScale.caption)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var against: String {
        switch comparison.baselineKind {
        case .sameMonthLastYear(let month): return "vs \(DateText.month(month)) last year"
        case .firstMonths: return "vs your first three months"
        }
    }

    private var baselineText: String {
        switch comparison.baselineKind {
        case .sameMonthLastYear(let month):
            return "\(DateText.monthAndYear(month)): \(NumberText.rate(comparison.baseline))."
        case .firstMonths(let from, let to):
            return "No readings from last year yet, so this compares with your first three months (\(DateText.short(from)) – \(DateText.short(to))): \(NumberText.rate(comparison.baseline))."
        }
    }
}
