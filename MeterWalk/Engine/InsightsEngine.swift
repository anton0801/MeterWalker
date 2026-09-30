//
//  InsightsEngine.swift
//  MeterWalk
//
//  The conclusions drawn from readings, tariffs and bills together.
//

import Foundation

struct CheapestTariffInsight: Identifiable, Equatable {
    var id: UUID { meter.id }
    let meter: Meter
    let window: ReplayWindow
    let result: ReplayResult
    let cheapest: TariffCost
    let current: TariffCost?

    /// How much less the cheapest would have cost than the current tariff.
    var saving: Double? {
        guard let current, cheapest.id != current.id else { return nil }
        let difference = current.total - cheapest.total
        return difference > 0 ? difference : nil
    }
}

struct OverbilledBill: Identifiable, Equatable {
    var id: UUID { bill.id }
    let bill: Bill
    let meter: Meter
    let result: BillCheckResult
}

struct CostPerDayInsight: Identifiable, Equatable {
    var id: UUID { meter.id }
    let meter: Meter
    let tariff: Tariff
    let perDay: Double
    let coveredDays: Int
}

struct ChangeInsight: Identifiable, Equatable {
    var id: UUID { meter.id }
    let meter: Meter
    let comparison: YearComparison
}

struct MonthlyInsight: Identifiable, Equatable {
    var id: UUID { meter.id }
    let meter: Meter
    let months: [ConsumptionEngine.MonthPair]
}

struct InsightsReport: Equatable {
    /// True once at least one meter has a daily rate.
    let hasDailyRate: Bool
    let cheapest: [CheapestTariffInsight]
    let overbilled: [OverbilledBill]
    let estimatedBillCount: Int
    let checkedBillCount: Int
    let monthly: [MonthlyInsight]
    let changes: [ChangeInsight]
    let costPerDay: [CostPerDayInsight]

    var overbilledMoney: Double {
        overbilled.compactMap { $0.result.excessMoney }.reduce(0, +)
    }
}

enum InsightsEngine {
    static func report(state: AppState, now: Date = Date()) -> InsightsReport {
        var cheapest: [CheapestTariffInsight] = []
        var monthly: [MonthlyInsight] = []
        var changes: [ChangeInsight] = []
        var costPerDay: [CostPerDayInsight] = []
        var hasDailyRate = false

        for meter in state.meters {
            let series = ConsumptionEngine.dailySeries(meter: meter, readings: state.readings)
            guard !series.isEmpty else { continue }
            hasDailyRate = true

            monthly.append(MonthlyInsight(meter: meter, months: ConsumptionEngine.twelveMonths(series: series, now: now)))

            if let comparison = ConsumptionEngine.yearComparison(series: series, now: now) {
                changes.append(ChangeInsight(meter: meter, comparison: comparison))
            }

            let tariffs = state.tariffs(for: meter.kind.tariffType)
            if !tariffs.isEmpty {
                let window = ReplayWindow.months12
                let range = window.range(now: now, series: series)
                let result = TariffEngine.replay(meter: meter, series: series, tariffs: tariffs, from: range.from, to: range.to)
                if result.coveredDays > 0, let best = result.cheapest, tariffs.count > 1 {
                    cheapest.append(CheapestTariffInsight(meter: meter, window: window, result: result, cheapest: best, current: result.current))
                }

                // Cost per day over roughly the last quarter, on the current tariff.
                let quarter = ReplayWindow.months3.range(now: now, series: series)
                let recent = TariffEngine.replay(meter: meter, series: series, tariffs: tariffs, from: quarter.from, to: quarter.to)
                if let current = recent.current, recent.coveredDays > 0 {
                    costPerDay.append(CostPerDayInsight(
                        meter: meter, tariff: current.tariff,
                        perDay: (current.standing + current.energy) / Double(recent.coveredDays),
                        coveredDays: recent.coveredDays
                    ))
                }
            }
        }

        var overbilled: [OverbilledBill] = []
        var checked = 0
        for bill in state.bills {
            guard let meter = state.meter(bill.meterID) else { continue }
            let result = BillCheckEngine.check(
                bill: bill, meter: meter, readings: state.readings,
                currentTariff: state.currentTariff(for: meter.kind.tariffType)
            )
            switch result.status {
            case .matches, .underbilled:
                checked += 1
            case .overbilled:
                checked += 1
                overbilled.append(OverbilledBill(bill: bill, meter: meter, result: result))
            case .noMeter, .noBillReadings, .notEnoughReadings:
                break
            }
        }

        return InsightsReport(
            hasDailyRate: hasDailyRate,
            cheapest: cheapest,
            overbilled: overbilled,
            estimatedBillCount: state.bills.filter { $0.readingType == .estimated }.count,
            checkedBillCount: checked,
            monthly: monthly,
            changes: changes,
            costPerDay: costPerDay
        )
    }
}
