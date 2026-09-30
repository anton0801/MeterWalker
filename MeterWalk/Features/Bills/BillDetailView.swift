//
//  BillDetailView.swift
//  MeterWalk
//
//  Bill Check: the readings on the bill next to the user's own photos,
//  worked out for the same dates. Produces an evidence pack; it does not
//  write a complaint or judge the chances of one.
//

import SwiftUI

struct BillDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let billID: UUID

    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var sharing: SharedFile?

    var body: some View {
        Group {
            if let bill = store.state.bills.first(where: { $0.id == billID }) {
                content(bill)
            } else {
                ScreenScroll {
                    EmptyStatePanel(symbol: "doc", title: "Bill removed", message: "This bill is no longer in the app.")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharing) { file in
            ShareSheet(items: [file.url])
                .ignoresSafeArea()
        }
    }

    private func content(_ bill: Bill) -> some View {
        let meter = store.state.meter(bill.meterID)
        let tariff = meter.flatMap { store.state.currentTariff(for: $0.kind.tariffType) }
        let result = BillCheckEngine.check(bill: bill, meter: meter, readings: store.state.readings, currentTariff: tariff)

        return ScreenScroll(spacing: 22) {
            ScreenTitle(
                bill.supplier.isEmpty ? "bill" : bill.supplier,
                subtitle: "\(DateText.full(bill.periodFrom)) – \(DateText.full(bill.periodTo))"
            )

            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.money.exact(bill.amount))
                        .font(TypeScale.money)
                        .foregroundStyle(Palette.white)
                    KeyValueRow(key: "Reading Type", value: bill.readingType.title, valueColor: bill.readingType == .estimated ? Palette.blue : Palette.white)
                    if let meter {
                        KeyValueRow(key: "Meter", value: meter.name)
                        ForEach(bill.readings, id: \.register) { item in
                            let prefix = item.register == .total ? "" : "\(item.register.title) "
                            if let opening = item.opening {
                                KeyValueRow(key: "\(prefix)Opening", value: meter.dialText(opening), mono: true)
                            }
                            if let closing = item.closing {
                                KeyValueRow(key: "\(prefix)Closing", value: meter.dialText(closing), mono: true)
                            }
                        }
                    } else {
                        KeyValueRow(key: "Meter", value: "Not linked", valueColor: Palette.tertiaryText)
                    }
                    let days = ConsumptionEngine.daysBetween(bill.periodFrom, bill.periodTo)
                    if days > 0 {
                        KeyValueRow(key: "Per day billed", value: store.money.exact(bill.amount / Double(days)), mono: true)
                    }
                    if !bill.notes.isEmpty {
                        Divider2()
                        Text(bill.notes).font(TypeScale.body).foregroundStyle(Palette.secondaryText)
                    }
                }
            }

            TitledSection(title: "Bill check") {
                checkPanel(bill: bill, meter: meter, result: result)
            }

            if let meter, [.overbilled, .underbilled, .matches].contains(result.status) {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Make Evidence Pack") { makePack(bill: bill, meter: meter, result: result) }
                        .buttonStyle(.primary)
                    Text("A PDF with the bill, your dated meter photos and the calculation, to send with a query. It does not write a complaint for you.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if bill.photoFile != nil {
                TitledSection(title: "Bill photo") {
                    PhotoPanel(fileName: bill.photoFile, height: 240)
                }
            }

            VStack(spacing: 12) {
                Button("Edit Bill") { editing = true }
                    .buttonStyle(.secondary)
                Button("Delete Bill") { confirmingDelete = true }
                    .buttonStyle(.destructive)
            }
        }
        .sheet(isPresented: $editing) {
            BillEditorView(bill: bill)
        }
        .alert("Delete this bill?", isPresented: $confirmingDelete) {
            Button("Delete Bill and Photo", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { store.deleteBill(bill.id) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Check

    @ViewBuilder
    private func checkPanel(bill: Bill, meter: Meter?, result: BillCheckResult) -> some View {
        switch result.status {
        case .noMeter:
            Panel {
                AssumptionNote(text: "Link this bill to a meter to compare it with your readings.", symbol: "link")
            }
        case .noBillReadings:
            Panel {
                AssumptionNote(text: "Add the opening and closing readings printed on the bill to check it against your photos.", symbol: "number")
            }
        case .notEnoughReadings:
            Panel {
                AssumptionNote(text: "Your readings do not reach these dates yet. A reading within 45 days of each bill date, with a daily rate, is needed.", symbol: "hourglass")
            }
        case .matches, .overbilled, .underbilled:
            if let meter {
                resultPanel(bill: bill, meter: meter, result: result)
            }
        }
    }

    private func resultPanel(bill: Bill, meter: Meter, result: BillCheckResult) -> some View {
        let color: Color = result.status == .overbilled ? Palette.red : (result.status == .underbilled ? Palette.blue : Palette.ghost)
        return VStack(alignment: .leading, spacing: 14) {
            Text(summary(bill: bill, meter: meter, result: result))
                .font(TypeScale.bodyEmphasis)
                .foregroundStyle(Palette.white)
                .fixedSize(horizontal: false, vertical: true)

            if let money = result.excessMoney, result.status == .overbilled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About \(store.money.exact(money))")
                        .font(TypeScale.moneySmall)
                        .foregroundStyle(Palette.red)
                    if let source = result.rateSource {
                        AssumptionNote(text: "Worked out \(source).")
                    }
                }
            }

            ForEach(result.checks) { check in
                registerDetail(check, bill: bill, meter: meter)
            }

            AssumptionNote(text: "Dates without a photo are worked out at the daily rate between your nearest photos.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous).fill(Palette.panel))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
                .strokeBorder(color, lineWidth: Metrics.borderWidth)
        )
    }

    /// "Estimated on the bill: 04350. Your photo on the same date: 04211.
    /// You were billed for 139 kWh you have not used."
    private func summary(bill: Bill, meter: Meter, result: BillCheckResult) -> String {
        let label: String
        switch bill.readingType {
        case .estimated: label = "Estimated on the bill"
        case .actual: label = "Actual reading on the bill"
        case .customer: label = "Your submitted reading on the bill"
        }
        var parts: [String] = []
        if let check = result.checks.first(where: { $0.billClosing != nil && $0.ownClosing != nil }), meter.registers.count == 1,
           let billClosing = check.billClosing, let own = check.ownClosing {
            parts.append("\(label): \(meter.dialText(billClosing)).")
            switch own.method {
            case .photo:
                parts.append("Your photo on the same date: \(meter.dialText(own.value)).")
            case .interpolated, .extrapolated:
                parts.append("Your photos, worked out for the same date: \(meter.dialText(own.value)).")
            }
        }
        let units = NumberText.use(abs(result.excessUnits ?? 0))
        switch result.status {
        case .overbilled:
            parts.append("You were billed for \(units) \(meter.unit) you have not used.")
        case .underbilled:
            parts.append("The bill is \(units) \(meter.unit) behind your meter. That use has not been charged yet and usually appears on a later bill.")
        case .matches:
            parts.append("The bill matches your meter.")
        default:
            break
        }
        return parts.joined(separator: " ")
    }

    private func registerDetail(_ check: RegisterCheck, bill: Bill, meter: Meter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if check.register != .total {
                SectionHeader("\(check.register.title) register \(check.register.meterLabel)")
            }
            if let billValue = check.billClosing {
                compareRow(title: "Closing, \(DateText.short(bill.periodTo))", bill: billValue, own: check.ownClosing, meter: meter)
            }
            if let billValue = check.billOpening {
                compareRow(title: "Opening, \(DateText.short(bill.periodFrom))", bill: billValue, own: check.ownOpening, meter: meter)
            }
            if let billed = check.billedUse, let own = check.ownUse {
                HStack {
                    Text("Use: billed \(NumberText.use(billed)), meter \(NumberText.use(own)) \(meter.unit)")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .padding(12)
        .background(RecessedShape())
    }

    private func compareRow(title: String, bill billValue: Double, own: OwnValue?, meter: Meter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TypeScale.captionEmphasis)
                .foregroundStyle(Palette.secondaryText)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bill").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.tertiaryText)
                    Text(meter.dialText(billValue))
                        .font(TypeScale.mono(17))
                        .foregroundStyle(Palette.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your meter").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.tertiaryText)
                    Text(own.map { meter.dialText($0.value) } ?? "—")
                        .font(TypeScale.mono(17))
                        .foregroundStyle(Palette.utility(meter.utility))
                }
                Spacer()
                if let own {
                    let diff = billValue - own.value
                    Text(diff > 0 ? "+\(NumberText.use(diff))" : NumberText.use(diff))
                        .font(TypeScale.mono(15, weight: .semibold))
                        .foregroundStyle(diff > 0.5 ? Palette.red : Palette.secondaryText)
                }
            }
            if let own {
                HStack(spacing: 8) {
                    ForEach(own.readingsUsed) { reading in
                        PhotoThumb(fileName: reading.photoFile, size: 36, cornerRadius: 6)
                    }
                    Text(EvidencePackBuilder.methodText(own, meter: meter).trimmingCharacters(in: CharacterSet(charactersIn: "()")))
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No photo close enough to this date.")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
    }

    private func makePack(bill: Bill, meter: Meter, result: BillCheckResult) {
        do {
            let url = try EvidencePackBuilder.build(bill: bill, meter: meter, result: result, photos: store.photos, money: store.money)
            sharing = SharedFile(url: url)
        } catch {
            store.errorMessage = "The evidence pack could not be made: \(error.localizedDescription)"
        }
    }
}
