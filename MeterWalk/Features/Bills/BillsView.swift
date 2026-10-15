//
//  BillsView.swift
//  MeterWalk
//

import SwiftUI

struct BillsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var adding = false

    private var bills: [Bill] {
        store.state.bills.sorted { $0.periodTo > $1.periodTo }
    }

    var body: some View {
        ScreenScroll(spacing: 22) {
            ScreenTitle(text: "bills", subtitle: "Checked against your own meter photos.") {
                IconButton(symbol: "plus", label: "Add bill", color: Palette.yellow) { adding = true }
            }

            ListStateContainer {
                if bills.isEmpty {
                    EmptyStatePanel(
                        symbol: "doc.text.fill",
                        title: "No bills yet",
                        message: "Add a bill with the readings printed on it. Meter Walk compares them with your photos taken nearest those dates, so an estimate shows up for what it is.",
                        actionTitle: "Add a Bill"
                    ) { adding = true }
                } else {
                    VStack(spacing: 10) {
                        ForEach(bills) { bill in
                            NavigationLink(value: Route.bill(bill.id)) {
                                BillRow(bill: bill)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $adding) {
            BillEditorView(bill: nil)
        }
    }
}

struct BillRow: View {
    @EnvironmentObject private var store: AppStore
    let bill: Bill

    private var meter: MeterItem? { store.state.meter(bill.meterID) }

    private var result: BillCheckResult {
        BillCheckEngine.check(
            bill: bill, meter: meter, readings: store.state.readings,
            currentTariff: meter.flatMap { store.state.currentTariff(for: $0.kind.tariffType) }
        )
    }

    var body: some View {
        let result = self.result
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let meter {
                        Image(systemName: meter.kind.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.utility(meter.utility))
                    }
                    Text(bill.supplier.isEmpty ? (meter?.name ?? "Bill") : bill.supplier)
                        .font(TypeScale.bodyEmphasis)
                        .foregroundStyle(Palette.white)
                        .lineLimit(1)
                    Spacer()
                    Text(store.money.total(bill.amount))
                        .font(TypeScale.mono(16))
                        .foregroundStyle(Palette.white)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryText)
                }
                HStack(spacing: 8) {
                    Text("\(DateText.short(bill.periodFrom)) – \(DateText.short(bill.periodTo))")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.secondaryText)
                    Badge(text: bill.readingType.title, color: bill.readingType == .estimated ? Palette.blue : Palette.tertiaryText)
                    Spacer()
                    BillStatusLabel(result: result, unit: meter?.unit ?? "")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BillStatusLabel: View {
    let result: BillCheckResult
    let unit: String

    var body: some View {
        switch result.status {
        case .overbilled:
            Label("+\(NumberText.use(result.excessUnits ?? 0)) \(unit)", systemImage: "exclamationmark.triangle.fill")
                .font(TypeScale.captionEmphasis)
                .foregroundStyle(Palette.red)
        case .underbilled:
            Label("\(NumberText.use(result.excessUnits ?? 0)) \(unit)", systemImage: "arrow.down.right")
                .font(TypeScale.captionEmphasis)
                .foregroundStyle(Palette.blue)
        case .matches:
            Label("Matches", systemImage: "checkmark")
                .font(TypeScale.captionEmphasis)
                .foregroundStyle(Palette.white)
        case .notEnoughReadings, .noBillReadings, .noMeter:
            Text("Not checked")
                .font(TypeScale.caption)
                .foregroundStyle(Palette.tertiaryText)
        }
    }
}
