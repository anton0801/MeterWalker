//
//  TariffDetailView.swift
//  MeterWalk
//

import SwiftUI

struct TariffDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let tariffID: UUID

    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if let tariff = store.state.tariffs.first(where: { $0.id == tariffID }) {
                content(tariff)
            } else {
                ScreenScroll {
                    EmptyStatePanel(symbol: "tag", title: "Tariff removed", message: "This tariff is no longer in the app.")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ tariff: Tariff) -> some View {
        let money = store.money
        let unit = tariff.meterType.unit
        return ScreenScroll(spacing: 20) {
            ScreenTitle(text: tariff.displayName, subtitle: [tariff.supplier, tariff.meterType.title].filter { !$0.isEmpty }.joined(separator: " · ")) {
                if tariff.isCurrent {
                    Badge(text: "Current", color: Palette.yellow, filled: true)
                }
            }

            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    KeyValueRow(key: "Type", value: tariff.structure.title)
                    KeyValueRow(key: "Standing Charge", value: "\(money.rate(tariff.standingChargePerDay)) a day", mono: true)
                    switch tariff.structure {
                    case .flat:
                        KeyValueRow(key: "Unit Rate", value: "\(money.rate(tariff.unitRate))/\(unit)", mono: true)
                    case .twoRate:
                        KeyValueRow(key: "Day Rate", value: "\(money.rate(tariff.dayRate))/\(unit)", mono: true)
                        KeyValueRow(key: "Night Rate", value: "\(money.rate(tariff.nightRate))/\(unit)", valueColor: Palette.blue, mono: true)
                        KeyValueRow(key: "Night Hours", value: "\(DateText.minutes(tariff.nightStartMinutes))–\(DateText.minutes(tariff.nightEndMinutes)) (\(NumberText.plain(tariff.nightHours)) h)", mono: true)
                    case .tiered:
                        let tiers = tariff.sortedTiers
                        ForEach(Array(tiers.enumerated()), id: \.element.id) { index, tier in
                            KeyValueRow(key: TariffEngine.tierLabel(index: index, tiers: tiers, unit: unit), value: money.rate(tier.rate), mono: true)
                        }
                    }
                    Divider2()
                    KeyValueRow(key: "Valid From", value: DateText.full(tariff.validFrom))
                    KeyValueRow(key: "Ends", value: tariff.endsOn.map(DateText.full) ?? "No end date")
                    KeyValueRow(key: "Exit Fee", value: tariff.exitFee > 0 ? money.total(tariff.exitFee) : "None", mono: true)
                    if !tariff.notes.isEmpty {
                        Divider2()
                        Text(tariff.notes)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }

            VStack(spacing: 12) {
                if let meter = store.state.meters.first(where: { $0.kind.tariffType == tariff.meterType }) {
                    NavigationLink(value: Route.tariffReplay(meter.id)) {
                        Text("Replay on My Use")
                    }
                    .buttonStyle(.primary)
                }
                if !tariff.isCurrent {
                    Button("Make This My Current Tariff") { store.makeCurrent(tariff.id) }
                        .buttonStyle(.secondary)
                }
                Button("Edit Tariff") { editing = true }
                    .buttonStyle(.secondary)
                Button("Delete Tariff") { confirmingDelete = true }
                    .buttonStyle(.destructive)
            }
        }
        .sheet(isPresented: $editing) {
            TariffEditorView(tariff: tariff)
        }
        .alert("Delete \(tariff.displayName)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { store.deleteTariff(tariff.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(tariff.isCurrent ? "It is your current tariff. Replays and bill checks will have no current tariff until you mark another." : "It will no longer appear in replays.")
        }
    }
}
