//
//  TariffEditorView.swift
//  MeterWalk
//
//  Every number is typed by the user from their own contract. Nothing is
//  pre-filled.
//

import SwiftUI

struct TariffEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let original: TariffItem?
    @State private var draft: TariffItem
    @State private var standing: String
    @State private var unitRate: String
    @State private var dayRate: String
    @State private var nightRate: String
    @State private var exitFee: String
    @State private var tiers: [TierDraft]
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var nightStart: Date
    @State private var nightEnd: Date

    struct TierDraft: Identifiable, Equatable {
        let id = UUID()
        var upTo: String
        var rate: String
    }

    init(tariff: TariffItem?, meterType: TariffMeterType? = nil) {
        original = tariff
        var base = tariff ?? TariffItem()
        if tariff == nil, let meterType { base.meterType = meterType }
        _draft = State(initialValue: base)
        _standing = State(initialValue: tariff.map { NumberText.editable($0.standingChargePerDay) } ?? "")
        _unitRate = State(initialValue: tariff.map { NumberText.editable($0.unitRate) } ?? "")
        _dayRate = State(initialValue: tariff.map { NumberText.editable($0.dayRate) } ?? "")
        _nightRate = State(initialValue: tariff.map { NumberText.editable($0.nightRate) } ?? "")
        _exitFee = State(initialValue: tariff.map { NumberText.editable($0.exitFee) } ?? "")
        let existingTiers = base.sortedTiers.map { TierDraft(upTo: $0.upTo.map { NumberText.editable($0) } ?? "", rate: NumberText.editable($0.rate)) }
        _tiers = State(initialValue: existingTiers.isEmpty ? [TierDraft(upTo: "", rate: ""), TierDraft(upTo: "", rate: "")] : existingTiers)
        _hasEndDate = State(initialValue: base.endsOn != nil)
        _endDate = State(initialValue: base.endsOn ?? ConsumptionEngine.addMonths(12, to: Date()))
        _nightStart = State(initialValue: TariffEditorView.time(minutes: base.nightStartMinutes))
        _nightEnd = State(initialValue: TariffEditorView.time(minutes: base.nightEndMinutes))
    }

    private static func time(minutes: Int) -> Date {
        ConsumptionEngine.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minutes(_ date: Date) -> Int {
        let c = ConsumptionEngine.calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private var unit: String { draft.meterType.unit }
    private var currency: String { store.money.symbol }

    // MARK: Validation

    private var problems: [String] {
        var result: [String] = []
        if NumberText.parse(standing) == nil { result.append("Enter the standing charge per day (0 if there is none).") }
        switch draft.structure {
        case .flat:
            if NumberText.parse(unitRate) == nil { result.append("Enter the unit rate.") }
        case .twoRate:
            if NumberText.parse(dayRate) == nil || NumberText.parse(nightRate) == nil {
                result.append("Enter both the day and the night rate.")
            }
        case .tiered:
            let parsed = parsedTiers
            if parsed == nil {
                result.append("Every step needs a rate, and every step but the last needs a limit.")
            } else if let parsed {
                let limits = parsed.compactMap(\.upTo)
                if limits != limits.sorted() || Set(limits).count != limits.count {
                    result.append("Step limits must go up from one step to the next.")
                }
            }
        }
        if !exitFee.isEmpty && NumberText.parse(exitFee) == nil { result.append("The exit fee is not a number.") }
        return result
    }

    private var parsedTiers: [TariffTier]? {
        let filled = tiers.filter { !$0.rate.isEmpty || !$0.upTo.isEmpty }
        guard !filled.isEmpty else { return nil }
        var result: [TariffTier] = []
        for (index, tier) in filled.enumerated() {
            guard let rate = NumberText.parse(tier.rate) else { return nil }
            let isLast = index == filled.count - 1
            if isLast {
                result.append(TariffTier(upTo: nil, rate: rate))
            } else {
                guard let upTo = NumberText.parse(tier.upTo), upTo > 0 else { return nil }
                result.append(TariffTier(upTo: upTo, rate: rate))
            }
        }
        return result
    }

    var body: some View {
        EditorSheet(
            title: original == nil ? "New Tariff" : "Edit Tariff",
            canSave: problems.isEmpty,
            onCancel: { dismiss() },
            onSave: save
        ) {
            TextFieldBox(title: "Tariff Name", text: $draft.name, placeholder: "As on your contract")
            TextFieldBox(title: "Supplier", text: $draft.supplier, placeholder: "Who sells it")

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Meter Type")
                SegmentPicker(options: TariffMeterType.allCases, selection: $draft.meterType) { $0.title }
            }
            .onChange(of: draft.meterType) { type in
                if !type.allowsTwoRate && draft.structure == .twoRate { draft.structure = .flat }
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Type")
                SegmentPicker(
                    options: draft.meterType.allowsTwoRate ? TariffStructure.allCases : [.flat, .tiered],
                    selection: $draft.structure
                ) { $0.title }
            }

            NumberFieldBox(title: "Standing Charge per Day", text: $standing, unit: "\(currency)/day", placeholder: "0.00")

            switch draft.structure {
            case .flat:
                NumberFieldBox(title: "Unit Rate", text: $unitRate, unit: "\(currency)/\(unit)", placeholder: "0.00")
            case .twoRate:
                NumberFieldBox(title: "Day Rate", text: $dayRate, unit: "\(currency)/\(unit)", placeholder: "0.00")
                NumberFieldBox(title: "Night Rate", text: $nightRate, unit: "\(currency)/\(unit)", placeholder: "0.00")
                Panel(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        FieldLabel(text: "Night Hours")
                        DateRow(title: "From", date: $nightStart, components: [.hourAndMinute])
                        DateRow(title: "To", date: $nightEnd, components: [.hourAndMinute])
                    }
                }
            case .tiered:
                tierEditor
            }

            Panel(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    DateRow(title: "Valid From", date: $draft.validFrom)
                    Divider2()
                    ToggleRow(title: "Has an End Date", detail: "You are reminded two weeks before it ends.", isOn: $hasEndDate)
                    if hasEndDate {
                        DateRow(title: "Ends On", date: $endDate)
                    }
                }
            }

            NumberFieldBox(title: "Exit Fee", text: $exitFee, unit: currency, placeholder: "0", hint: "charged for leaving early")

            Panel(padding: 14) {
                ToggleRow(
                    title: "This Is My Current Tariff",
                    detail: "Used for what you paid and for bill checks. Only one tariff per meter type is current.",
                    isOn: $draft.isCurrent
                )
            }

            TextFieldBox(title: "Notes", text: $draft.notes, placeholder: "Optional", capitalization: .sentences, axis: .vertical)

            if !problems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(problems, id: \.self) { problem in
                        AssumptionNote(text: problem, symbol: "exclamationmark.circle", color: Palette.tertiaryText)
                    }
                }
            }
        }
    }

    private var tierEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(text: "Tiers with Thresholds", hint: "per calendar month")
            ForEach(Array(tiers.enumerated()), id: \.element.id) { index, _ in
                Panel(padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Step \(index + 1)")
                                .font(TypeScale.captionEmphasis)
                                .foregroundStyle(Palette.white)
                            Spacer()
                            if tiers.count > 1 {
                                Button {
                                    tiers.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(Palette.red)
                                }
                                .accessibilityLabel("Remove step \(index + 1)")
                            }
                        }
                        if index < tiers.count - 1 {
                            NumberFieldBox(title: "Up to", text: $tiers[index].upTo, unit: "\(unit)/month", placeholder: "0")
                        } else {
                            Text(tiers.count == 1 ? "All use" : "Everything above the last limit")
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.tertiaryText)
                        }
                        NumberFieldBox(title: "Rate", text: $tiers[index].rate, unit: "\(currency)/\(unit)", placeholder: "0.00")
                    }
                }
            }
            Button("Add a Step") { tiers.append(TierDraft(upTo: "", rate: "")) }
                .buttonStyle(InlineButtonStyle())
        }
    }

    private func save() {
        guard problems.isEmpty else { return }
        var tariff = draft
        tariff.name = tariff.name.trimmingCharacters(in: .whitespacesAndNewlines)
        tariff.supplier = tariff.supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        tariff.standingChargePerDay = NumberText.parse(standing) ?? 0
        tariff.exitFee = NumberText.parse(exitFee) ?? 0
        tariff.endsOn = hasEndDate ? endDate : nil
        switch tariff.structure {
        case .flat:
            tariff.unitRate = NumberText.parse(unitRate) ?? 0
        case .twoRate:
            tariff.dayRate = NumberText.parse(dayRate) ?? 0
            tariff.nightRate = NumberText.parse(nightRate) ?? 0
            tariff.nightStartMinutes = TariffEditorView.minutes(nightStart)
            tariff.nightEndMinutes = TariffEditorView.minutes(nightEnd)
        case .tiered:
            tariff.tiers = parsedTiers ?? []
        }
        store.saveTariff(tariff)
        dismiss()
    }
}
