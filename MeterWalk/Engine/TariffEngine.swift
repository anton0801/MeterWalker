//
//  TariffEngine.swift
//  MeterWalk
//
//  Tariff Replay: the user's real use over a period, priced on every tariff
//  they entered.
//
//      cost = standing charge × days + Σ(use in zone × zone price)
//
//  Tiered tariffs split each calendar month's use across the thresholds.
//

import Foundation

enum ReplayWindow: String, CaseIterable, Identifiable {
    case months3, months6, months12, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .months3: return "3 Months"
        case .months6: return "6 Months"
        case .months12: return "12 Months"
        case .all: return "All"
        }
    }

    var phrase: String {
        switch self {
        case .months3: return "Over the last 3 months"
        case .months6: return "Over the last 6 months"
        case .months12: return "Over the last 12 months"
        case .all: return "Since your first reading"
        }
    }

    /// [from, to) as calendar days, ending with today.
    func range(now: Date, series: [Date: DayUse]) -> (from: Date, to: Date) {
        let to = ConsumptionEngine.addDays(1, to: ConsumptionEngine.day(now))
        let from: Date
        switch self {
        case .months3: from = ConsumptionEngine.addMonths(-3, to: to)
        case .months6: from = ConsumptionEngine.addMonths(-6, to: to)
        case .months12: from = ConsumptionEngine.addMonths(-12, to: to)
        case .all: from = series.keys.min() ?? ConsumptionEngine.day(now)
        }
        return (from, to)
    }
}

struct CostLine: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let quantity: Double
    let rate: Double
    var amount: Double { quantity * rate }
}

struct TariffCost: Identifiable, Equatable {
    var id: UUID { tariff.id }
    let tariff: Tariff
    let standing: Double
    let energyLines: [CostLine]
    /// Exit fee of the current tariff, paid to switch to this one.
    let exitFee: Double
    /// The night share the user set, when a single-rate meter is priced on a
    /// two-rate tariff.
    let nightShareAssumption: Double?
    /// True when some months were only partly covered and the thresholds were
    /// scaled to the covered days.
    let proratedTiers: Bool
    /// Why this tariff cannot be priced, if it cannot.
    let unavailableReason: String?

    var energy: Double { energyLines.reduce(0) { $0 + $1.amount } }
    var total: Double { standing + energy + exitFee }
    var isAvailable: Bool { unavailableReason == nil }
    var isCurrent: Bool { tariff.isCurrent }
}

struct ReplayResult: Equatable {
    let from: Date
    let to: Date
    let periodDays: Int
    let coveredDays: Int
    let totalUse: Double
    /// Separate day and night use, only for two-rate meters.
    let dayUse: Double?
    let nightUse: Double?
    let costs: [TariffCost]

    var current: TariffCost? { costs.first { $0.isCurrent && $0.isAvailable } }

    var cheapest: TariffCost? {
        costs.filter(\.isAvailable).min { $0.total < $1.total }
    }

    var cheapestAlternative: TariffCost? {
        costs.filter { $0.isAvailable && !$0.isCurrent }.min { $0.total < $1.total }
    }

    var needsNightShare: Bool {
        costs.contains { $0.unavailableReason == TariffEngine.nightShareMissing }
    }

    var usesNightShareAssumption: Double? {
        costs.compactMap(\.nightShareAssumption).first
    }

    var hasProratedTiers: Bool { costs.contains { $0.proratedTiers } }
}

enum TariffEngine {
    static let nightShareMissing = "Set the share of your use at night to price this tariff."

    static func replay(meter: Meter, readings: [Reading], tariffs: [Tariff], from: Date, to: Date) -> ReplayResult {
        let series = ConsumptionEngine.dailySeries(meter: meter, readings: readings)
        return replay(meter: meter, series: series, tariffs: tariffs, from: from, to: to)
    }

    static func replay(meter: Meter, series: [Date: DayUse], tariffs: [Tariff], from: Date, to: Date) -> ReplayResult {
        let days = series.values.filter { $0.day >= from && $0.day < to }
        let totalUse = days.reduce(0) { $0 + $1.total }
        let dayUse = meter.kind.isTwoRate ? days.reduce(0) { $0 + $1.use(.day) } : nil
        let nightUse = meter.kind.isTwoRate ? days.reduce(0) { $0 + $1.use(.night) } : nil

        let relevant = tariffs.filter { $0.meterType == meter.kind.tariffType }
        let current = relevant.first { $0.isCurrent }

        let costs = relevant.map { tariff in
            cost(of: tariff, meter: meter, days: days, dayUse: dayUse, nightUse: nightUse,
                 totalUse: totalUse, exitFee: (tariff.isCurrent ? 0 : current?.exitFee ?? 0))
        }
        .sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            switch (lhs.isAvailable, rhs.isAvailable) {
            case (true, false): return true
            case (false, true): return false
            default: return lhs.total < rhs.total
            }
        }

        return ReplayResult(
            from: from,
            to: to,
            periodDays: max(0, ConsumptionEngine.daysBetween(from, to)),
            coveredDays: days.count,
            totalUse: totalUse,
            dayUse: dayUse,
            nightUse: nightUse,
            costs: costs
        )
    }

    static func cost(
        of tariff: Tariff,
        meter: Meter,
        days: [DayUse],
        dayUse: Double?,
        nightUse: Double?,
        totalUse: Double,
        exitFee: Double
    ) -> TariffCost {
        let standing = tariff.standingChargePerDay * Double(days.count)
        let unit = meter.unit

        switch tariff.structure {
        case .flat:
            return TariffCost(
                tariff: tariff, standing: standing,
                energyLines: [CostLine(label: "All use, \(unit)", quantity: totalUse, rate: tariff.unitRate)],
                exitFee: exitFee, nightShareAssumption: nil, proratedTiers: false, unavailableReason: nil
            )

        case .twoRate:
            if let dayUse, let nightUse {
                return TariffCost(
                    tariff: tariff, standing: standing,
                    energyLines: [
                        CostLine(label: "Day, \(unit)", quantity: dayUse, rate: tariff.dayRate),
                        CostLine(label: "Night, \(unit)", quantity: nightUse, rate: tariff.nightRate),
                    ],
                    exitFee: exitFee, nightShareAssumption: nil, proratedTiers: false, unavailableReason: nil
                )
            }
            // A single-rate meter cannot tell day from night. Use only the
            // share the user set; never guess one.
            guard let share = meter.nightShareAssumption else {
                return TariffCost(
                    tariff: tariff, standing: standing, energyLines: [], exitFee: exitFee,
                    nightShareAssumption: nil, proratedTiers: false, unavailableReason: nightShareMissing
                )
            }
            return TariffCost(
                tariff: tariff, standing: standing,
                energyLines: [
                    CostLine(label: "Day (assumed), \(unit)", quantity: totalUse * (1 - share), rate: tariff.dayRate),
                    CostLine(label: "Night (assumed), \(unit)", quantity: totalUse * share, rate: tariff.nightRate),
                ],
                exitFee: exitFee, nightShareAssumption: share, proratedTiers: false, unavailableReason: nil
            )

        case .tiered:
            let tiers = tariff.sortedTiers
            guard !tiers.isEmpty else {
                return TariffCost(
                    tariff: tariff, standing: standing, energyLines: [], exitFee: exitFee,
                    nightShareAssumption: nil, proratedTiers: false,
                    unavailableReason: "Add at least one price step to this tariff."
                )
            }
            let split = tieredSplit(days: days, tiers: tiers)
            let lines = tiers.enumerated().map { index, tier -> CostLine in
                CostLine(label: tierLabel(index: index, tiers: tiers, unit: unit), quantity: split.perTier[index], rate: tier.rate)
            }
            return TariffCost(
                tariff: tariff, standing: standing, energyLines: lines, exitFee: exitFee,
                nightShareAssumption: nil, proratedTiers: split.prorated, unavailableReason: nil
            )
        }
    }

    /// Splits use across tiers month by month. Thresholds are monthly; a
    /// month the readings only partly cover gets thresholds scaled to the
    /// covered days, so a half month is not priced as if it were cheap.
    static func tieredSplit(days: [DayUse], tiers: [TariffTier]) -> (perTier: [Double], prorated: Bool) {
        var perTier = Array(repeating: 0.0, count: tiers.count)
        var prorated = false
        let byMonth = Dictionary(grouping: days) { ConsumptionEngine.monthStart($0.day) }
        for (month, monthDays) in byMonth {
            let daysInMonth = ConsumptionEngine.calendar.range(of: .day, in: .month, for: month)?.count ?? 30
            let fraction = min(1, Double(monthDays.count) / Double(daysInMonth))
            if fraction < 1 { prorated = true }
            var remaining = monthDays.reduce(0) { $0 + $1.total }
            var lower = 0.0
            for (index, tier) in tiers.enumerated() {
                guard remaining > 0 else { break }
                if let upTo = tier.upTo {
                    let cap = max(0, upTo * fraction - lower)
                    let slice = min(remaining, cap)
                    perTier[index] += slice
                    remaining -= slice
                    lower = upTo * fraction
                } else {
                    perTier[index] += remaining
                    remaining = 0
                }
            }
            // Use above the last threshold, if the last step has a limit, is
            // priced at the last step's rate.
            if remaining > 0, !perTier.isEmpty {
                perTier[perTier.count - 1] += remaining
            }
        }
        return (perTier, prorated)
    }

    static func tierLabel(index: Int, tiers: [TariffTier], unit: String) -> String {
        let lower = index == 0 ? 0 : (tiers[index - 1].upTo ?? 0)
        if let upTo = tiers[index].upTo {
            return "\(NumberText.plain(lower))–\(NumberText.plain(upTo)) \(unit)/month"
        }
        return "Above \(NumberText.plain(lower)) \(unit)/month"
    }
}

// MARK: - Plain-language summary

enum ReplayNarrative {
    /// The one sentence the Tariff Replay screen leads with.
    static func sentence(result: ReplayResult, window: ReplayWindow, money: (Double) -> String) -> String {
        guard result.coveredDays > 0 else {
            return "Your readings do not reach into this period yet. Two readings a few weeks apart are enough to start."
        }
        let pricedCount = result.costs.filter(\.isAvailable).count
        guard let current = result.current else {
            if pricedCount == 0 {
                return "Add your current tariff to see what this use cost you."
            }
            return "Mark one tariff as your current one to see what you paid and what the others would have cost."
        }
        let paid = "\(window.phrase) you paid \(money(current.total))."
        guard let alternative = result.cheapestAlternative else {
            return "\(paid) Add another tariff to see what the same use would have cost on it."
        }
        if alternative.total < current.total {
            var text = "\(paid) On \(alternative.tariff.displayName) the same use would have cost \(money(alternative.total))"
            if alternative.exitFee > 0 {
                text += ", including the exit fee of \(money(alternative.exitFee))"
            }
            return text + "."
        }
        let others = result.costs.filter { $0.isAvailable && !$0.isCurrent }.count
        let noun = others == 1 ? "tariff" : "tariffs"
        return "\(paid) None of the other \(others) \(noun) would have cost less for the same use. The closest, \(alternative.tariff.displayName), comes to \(money(alternative.total))."
    }

    static func assumptionNote(share: Double) -> String {
        "Assumes \(Int((share * 100).rounded()))% of your use is at night, as you set it."
    }

    static func coverageNote(result: ReplayResult) -> String? {
        guard result.coveredDays > 0, result.coveredDays < result.periodDays else { return nil }
        return "Your readings cover \(result.coveredDays) of these \(result.periodDays) days. Every tariff is priced for the same \(result.coveredDays) days."
    }

    static let calculatedNote = "Worked out from your readings on your current tariff, not taken from bills."
    static let proratedNote = "Tier thresholds are scaled down for months your readings only partly cover."
}

extension Tariff {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(structure.title) tariff" : trimmed
    }
}
