//
//  MeterComponents.swift
//  MeterWalk
//
//  The LCD panel for one meter: name, the latest reading per register over
//  unlit segments, and the latest daily rate.
//

import SwiftUI

struct MeterSummaryPanel: View {
    @EnvironmentObject private var store: AppStore
    let meter: Meter
    var compact = false
    var showsChevron = true

    private var accent: Color { Palette.utility(meter.utility) }

    private var latest: [Register: Reading] {
        var result: [Register: Reading] = [:]
        for register in meter.registers {
            result[register] = store.state.latestReading(for: meter.id, register: register)
        }
        return result
    }

    private var lastDate: Date? { latest.values.map(\.date).max() }

    private var rate: (rate: Double, since: Date, days: Int, rough: Bool)? {
        ConsumptionEngine.latestDailyRate(meter: meter, readings: store.state.readings)
    }

    private var isDue: Bool {
        guard let lastDate else { return true }
        return ConsumptionEngine.daysBetween(lastDate, Date()) > 31
    }

    var body: some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: meter.kind.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 26)
                        .background(RecessedShape(radius: 6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(meter.name)
                            .font(TypeScale.bodyEmphasis)
                            .foregroundStyle(Palette.white)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.tertiaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if isDue && lastDate != nil {
                        Badge(text: "Reading due", color: Palette.blue)
                    }
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }

                ForEach(meter.registers) { register in
                    RecessedDisplay(verticalPadding: compact ? 6 : 10) {
                        HStack(spacing: 10) {
                            if register != .total {
                                VStack(spacing: 0) {
                                    Text(register.meterLabel)
                                        .font(TypeScale.mono(12))
                                    Text(register.title.uppercased())
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .foregroundStyle(accent.opacity(0.8))
                                .frame(width: 36)
                            }
                            if let reading = latest[register] {
                                FittedLCD(
                                    text: meter.dialText(reading.value),
                                    maxSize: compact || meter.kind.isTwoRate ? 32 : 44,
                                    color: accent,
                                    unit: meter.unit
                                )
                            } else {
                                FittedLCD(
                                    text: meter.ghostText,
                                    maxSize: compact || meter.kind.isTwoRate ? 32 : 44,
                                    color: Palette.ghost,
                                    rollFromZero: false
                                )
                                .accessibilityLabel("No reading yet")
                            }
                        }
                    }
                }

                footer
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [meter.kind.title]
        if !meter.location.isEmpty { parts.append(meter.location) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var footer: some View {
        if let lastDate {
            HStack(spacing: 6) {
                Text("Read \(DateText.short(lastDate))")
                    .foregroundStyle(Palette.secondaryText)
                if let rate {
                    Text("·").foregroundStyle(Palette.tertiaryText)
                    Text("\(NumberText.rate(rate.rate)) \(meter.unit)/day")
                        .foregroundStyle(Palette.white)
                    if rate.rough {
                        Text("rough").foregroundStyle(Palette.tertiaryText)
                    }
                }
            }
            .font(TypeScale.caption)
        } else {
            Text("No reading yet. Tap the camera below to take one.")
                .font(TypeScale.caption)
                .foregroundStyle(Palette.secondaryText)
        }
    }
}

/// Small row for a reading in a history list.
struct ReadingRow: View {
    let meter: Meter
    let reading: Reading
    /// Daily rate of the interval that ends at this reading, if any.
    let interval: UseInterval?

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumb(fileName: reading.photoFile, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(meter.dialText(reading.value))
                    .font(TypeScale.mono(18))
                    .foregroundStyle(reading.isSetAside ? Palette.tertiaryText : Palette.utility(meter.utility))
                    .strikethrough(reading.isSetAside, color: Palette.tertiaryText)
                HStack(spacing: 6) {
                    Text(DateText.short(reading.date))
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.secondaryText)
                    flags
                }
            }
            Spacer(minLength: 6)
            if let interval, !reading.isSetAside {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(NumberText.rate(interval.dailyRate))
                        .font(TypeScale.mono(15, weight: .semibold))
                        .foregroundStyle(interval.isRough ? Palette.secondaryText : Palette.white)
                    Text(interval.isRough ? "per day, rough" : "per day")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var flags: some View {
        if reading.isSetAside {
            Badge(text: "Set aside", color: Palette.tertiaryText)
        } else if let reason = reading.dropReason, reason != .typo {
            Badge(text: reason.title, color: Palette.blue)
        } else if let ratio = reading.confirmedUnusualRatio {
            Badge(text: "×\(NumberText.one(ratio))", color: Palette.red)
        } else if reading.source == .typed {
            Image(systemName: "keyboard")
                .font(.system(size: 11))
                .foregroundStyle(Palette.tertiaryText)
                .accessibilityLabel("Typed, no photo")
        }
    }
}
