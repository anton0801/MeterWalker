//
//  AppliancesView.swift
//  MeterWalk
//
//  Rough per-device figures from the power and hours the user types. Always
//  labelled as estimates and never added to measured use.
//

import SwiftUI

struct AppliancesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: Appliance?
    @State private var adding = false

    private var unitRate: (rate: Double, tariff: TariffItem)? {
        guard let tariff = store.state.currentTariff(for: .electricity) else { return nil }
        switch tariff.structure {
        case .flat: return (tariff.unitRate, tariff)
        case .twoRate: return (tariff.dayRate, tariff)
        case .tiered: return tariff.sortedTiers.first.map { ($0.rate, tariff) }
        }
    }

    var body: some View {
        ScreenScroll(spacing: 22) {
            ScreenTitle(text: "appliances", subtitle: "Estimates from power and hours you enter.") {
                IconButton(symbol: "plus", label: "Add appliance", color: Palette.yellow) { adding = true }
            }

            AssumptionNote(
                text: "These are estimates, not measurements. They are kept apart from your meter readings and never added to them.",
                symbol: "info.circle",
                color: Palette.blue
            )

            ListStateContainer {
                if store.state.appliances.isEmpty {
                    EmptyStatePanel(
                        symbol: "powerplug.fill",
                        title: "No appliances yet",
                        message: "Add a device with its power in watts (on its label) and how long it runs a day, to see roughly what it uses.",
                        actionTitle: "Add an Appliance"
                    ) { adding = true }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(spacing: 10) {
                            ForEach(store.state.appliances.sorted { $0.kWhPerDay > $1.kWhPerDay }) { appliance in
                                Button { editing = appliance } label: { row(appliance) }
                                    .buttonStyle(.plain)
                            }
                        }
                        totals
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { ApplianceEditorView(appliance: nil) }
        .sheet(item: $editing) { ApplianceEditorView(appliance: $0) }
    }

    private func row(_ appliance: Appliance) -> some View {
        Panel(padding: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(appliance.name.isEmpty ? "Appliance" : appliance.name)
                            .font(TypeScale.bodyEmphasis)
                            .foregroundStyle(Palette.white)
                        Badge(text: "Estimate", color: Palette.tertiaryText)
                    }
                    Text("\(NumberText.plain(appliance.watts)) W × \(NumberText.plain(appliance.hoursPerDay)) h, \(appliance.daysPerWeek) days a week")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("~\(NumberText.rate(appliance.kWhPerDay))")
                        .font(TypeScale.mono(17))
                        .foregroundStyle(Palette.yellow.opacity(0.85))
                    Text("kWh/day")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryText)
                    if let unitRate {
                        Text("~\(store.money.exact(appliance.kWhPerDay * unitRate.rate))/day")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var totals: some View {
        let total = store.state.appliances.reduce(0) { $0 + $1.kWhPerDay }
        TitledSection(title: "Estimated together") {
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    KeyValueRow(key: "Per day", value: "~\(NumberText.rate(total)) kWh", mono: true)
                    KeyValueRow(key: "Per month", value: "~\(NumberText.use(total * 30.44)) kWh", mono: true)
                    if let unitRate {
                        KeyValueRow(key: "Per month, energy only", value: "~\(store.money.total(total * 30.44 * unitRate.rate))", mono: true)
                        AssumptionNote(text: "At \(store.money.rate(unitRate.rate))/kWh from \(unitRate.tariff.displayName)\(unitRate.tariff.structure == .flat ? "" : ", its \(unitRate.tariff.structure == .twoRate ? "day" : "first-step") rate"), without the standing charge.")
                    }
                    if let measured = measuredDaily {
                        Divider2()
                        Text("For scale, your electricity meter measured \(NumberText.rate(measured)) kWh a day over its latest readings. The estimates above are not part of that figure.")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var measuredDaily: Double? {
        let rates = store.state.meters
            .filter { $0.utility == .electricity }
            .compactMap { ConsumptionEngine.latestDailyRate(meter: $0, readings: store.state.readings)?.rate }
        return rates.isEmpty ? nil : rates.reduce(0, +)
    }
}

struct ApplianceEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let original: Appliance?
    @State private var draft: Appliance
    @State private var watts: String
    @State private var hours: String
    @State private var confirmingDelete = false

    init(appliance: Appliance?) {
        original = appliance
        _draft = State(initialValue: appliance ?? Appliance())
        _watts = State(initialValue: appliance.map { NumberText.editable($0.watts) } ?? "")
        _hours = State(initialValue: appliance.map { NumberText.editable($0.hoursPerDay) } ?? "")
    }

    private var canSave: Bool {
        guard let w = NumberText.parse(watts), let h = NumberText.parse(hours) else { return false }
        return w > 0 && h > 0 && h <= 24 && !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        EditorSheet(title: original == nil ? "New Appliance" : "Edit Appliance", canSave: canSave, onCancel: { dismiss() }, onSave: save) {
            TextFieldBox(title: "Name", text: $draft.name, placeholder: "Electric heater")
            NumberFieldBox(title: "Power", text: $watts, unit: "W", placeholder: "0", hint: "on the label or manual")
            NumberFieldBox(title: "Hours a Day", text: $hours, unit: "h", placeholder: "0", invalid: (NumberText.parse(hours) ?? 0) > 24)
            Panel(padding: 14) {
                StepperRow(title: "Days a Week", value: $draft.daysPerWeek, range: 1...7)
            }
            if let w = NumberText.parse(watts), let h = NumberText.parse(hours), w > 0, h > 0 {
                let preview = Appliance(watts: w, hoursPerDay: h, daysPerWeek: draft.daysPerWeek)
                AssumptionNote(text: "Estimate: about \(NumberText.rate(preview.kWhPerDay)) kWh a day, \(NumberText.use(preview.kWhPerMonth)) kWh a month. Devices that cycle, like fridges, use less than their rated power.")
            }
            TextFieldBox(title: "Notes", text: $draft.notes, placeholder: "Optional", capitalization: .sentences)
            if original != nil {
                Button("Delete Appliance") { confirmingDelete = true }
                    .buttonStyle(.destructive)
            }
        }
        .alert("Delete this appliance?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                if let original { store.deleteAppliance(original.id) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func save() {
        var appliance = draft
        appliance.name = appliance.name.trimmingCharacters(in: .whitespacesAndNewlines)
        appliance.watts = NumberText.parse(watts) ?? 0
        appliance.hoursPerDay = NumberText.parse(hours) ?? 0
        store.saveAppliance(appliance)
        dismiss()
    }
}
