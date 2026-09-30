//
//  ConsumptionEngine.swift
//  MeterWalk
//
//  Turns readings taken on odd dates into use per day:
//
//      daily use = (reading₂ − reading₁) ÷ days between the dates
//
//  For monthly figures each interval's use is spread evenly over its days.
//  Intervals longer than 45 days are flagged as rough.
//

import Foundation

/// Use between two consecutive counted readings of one register.
struct UseInterval: Identifiable, Equatable {
    var id: String { "\(startReadingID.uuidString)-\(endReadingID.uuidString)" }
    let meterID: UUID
    let register: Register
    /// Start of the calendar day of each reading.
    let startDay: Date
    let endDay: Date
    let startValue: Double
    let endValue: Double
    let use: Double
    let days: Int
    let rolledOver: Bool
    let startReadingID: UUID
    let endReadingID: UUID

    var dailyRate: Double { use / Double(days) }

    static let roughThresholdDays = 45
    var isRough: Bool { days > UseInterval.roughThresholdDays }
}

/// Use on one calendar day, per register.
struct DayUse: Equatable {
    let day: Date
    var perRegister: [Register: Double]
    var rough: Bool

    var total: Double { perRegister.values.reduce(0, +) }
    func use(_ register: Register) -> Double { perRegister[register] ?? 0 }
}

struct MonthUse: Equatable {
    /// First day of the month.
    let month: Date
    let total: Double
    let coveredDays: Int
    let daysInMonth: Int
    let rough: Bool

    var dailyAverage: Double? {
        coveredDays > 0 ? total / Double(coveredDays) : nil
    }
}

struct YearComparison: Equatable {
    enum Baseline: Equatable {
        /// The same calendar month one year earlier.
        case sameMonthLastYear(Date)
        /// No data from last year yet: the first three months of readings.
        case firstMonths(from: Date, to: Date)
    }

    let month: Date
    let current: Double
    let baseline: Double
    let baselineKind: Baseline
    let currentRough: Bool

    /// current ÷ baseline; 1 means the same as last year.
    var ratio: Double? { baseline > 0 ? current / baseline : nil }
    var changePercent: Double? { ratio.map { ($0 - 1) * 100 } }
}

enum ConsumptionEngine {
    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static func daysBetween(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents([.day], from: day(start), to: day(end)).day ?? 0
    }

    static func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? day(date)
    }

    static func addDays(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: date) ?? date
    }

    static func addMonths(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: n, to: date) ?? date
    }

    // MARK: Readings that count

    /// Counted readings of one register in date order, one per calendar day
    /// (the latest that day wins).
    static func countedReadings(_ readings: [Reading], meterID: UUID, register: Register) -> [Reading] {
        let relevant = readings
            .filter { $0.meterID == meterID && $0.register == register && !$0.isSetAside }
            .sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.createdAt < rhs.createdAt : lhs.date < rhs.date
            }
        var byDay: [Reading] = []
        for reading in relevant {
            if let last = byDay.last, day(last.date) == day(reading.date) {
                byDay[byDay.count - 1] = reading
            } else {
                byDay.append(reading)
            }
        }
        return byDay
    }

    // MARK: Intervals

    static func intervals(meter: Meter, register: Register, readings: [Reading]) -> [UseInterval] {
        let counted = countedReadings(readings, meterID: meter.id, register: register)
        guard counted.count >= 2 else { return [] }
        var result: [UseInterval] = []
        for index in 1..<counted.count {
            let previous = counted[index - 1]
            let current = counted[index]
            let days = daysBetween(previous.date, current.date)
            guard days > 0 else { continue }

            var use: Double
            var rolledOver = false
            switch current.dropReason {
            case .meterReplaced?:
                // A new meter: nothing can be worked out across the swap.
                continue
            case .rolledOver?:
                use = (meter.rolloverValue - previous.value) + current.value
                rolledOver = true
            case .typo?, nil:
                use = current.value - previous.value
            }
            // A drop with no reason would be a data error; it never counts as
            // negative use.
            guard use >= 0 else { continue }

            result.append(UseInterval(
                meterID: meter.id,
                register: register,
                startDay: day(previous.date),
                endDay: day(current.date),
                startValue: previous.value,
                endValue: current.value,
                use: use,
                days: days,
                rolledOver: rolledOver,
                startReadingID: previous.id,
                endReadingID: current.id
            ))
        }
        return result
    }

    static func intervals(meter: Meter, readings: [Reading]) -> [Register: [UseInterval]] {
        var result: [Register: [UseInterval]] = [:]
        for register in meter.registers {
            result[register] = intervals(meter: meter, register: register, readings: readings)
        }
        return result
    }

    // MARK: Daily series

    /// Use per calendar day. A day counts only when every register of the
    /// meter covers it, so a two-rate total is never half a day.
    static func dailySeries(meter: Meter, readings: [Reading]) -> [Date: DayUse] {
        let byRegister = intervals(meter: meter, readings: readings)
        var perRegisterDays: [Register: [Date: (Double, Bool)]] = [:]
        for (register, intervals) in byRegister {
            var days: [Date: (Double, Bool)] = [:]
            for interval in intervals {
                let rate = interval.dailyRate
                for offset in 0..<interval.days {
                    let d = addDays(offset, to: interval.startDay)
                    days[d] = (rate, interval.isRough)
                }
            }
            perRegisterDays[register] = days
        }

        guard let first = meter.registers.first, let firstDays = perRegisterDays[first] else { return [:] }
        var series: [Date: DayUse] = [:]
        for (d, _) in firstDays {
            var perRegister: [Register: Double] = [:]
            var rough = false
            var complete = true
            for register in meter.registers {
                guard let entry = perRegisterDays[register]?[d] else {
                    complete = false
                    break
                }
                perRegister[register] = entry.0
                rough = rough || entry.1
            }
            if complete {
                series[d] = DayUse(day: d, perRegister: perRegister, rough: rough)
            }
        }
        return series
    }

    // MARK: Months

    static func monthly(series: [Date: DayUse]) -> [Date: MonthUse] {
        var totals: [Date: (Double, Int, Bool)] = [:]
        for (d, use) in series {
            let m = monthStart(d)
            let existing = totals[m] ?? (0, 0, false)
            totals[m] = (existing.0 + use.total, existing.1 + 1, existing.2 || use.rough)
        }
        var result: [Date: MonthUse] = [:]
        for (m, value) in totals {
            let daysInMonth = calendar.range(of: .day, in: .month, for: m)?.count ?? 30
            result[m] = MonthUse(month: m, total: value.0, coveredDays: value.1, daysInMonth: daysInMonth, rough: value.2)
        }
        return result
    }

    struct MonthPair: Identifiable, Equatable {
        var id: Date { month }
        let month: Date
        let thisYear: MonthUse?
        let lastYear: MonthUse?
    }

    /// Twelve months ending with the month of `now`, each with the same month
    /// one year earlier.
    static func twelveMonths(series: [Date: DayUse], now: Date) -> [MonthPair] {
        let months = monthly(series: series)
        let current = monthStart(now)
        return (0..<12).reversed().map { back in
            let m = addMonths(-back, to: current)
            return MonthPair(month: m, thisYear: months[m], lastYear: months[addMonths(-12, to: m)])
        }
    }

    // MARK: Same time last year

    static func yearComparison(series: [Date: DayUse], now: Date) -> YearComparison? {
        let months = monthly(series: series)
        guard !months.isEmpty else { return nil }

        let thisMonth = monthStart(now)
        // This month if the readings reach it, otherwise the latest month they do.
        let month: Date
        if let use = months[thisMonth], use.coveredDays > 0 {
            month = thisMonth
        } else if let latest = months.keys.filter({ $0 <= thisMonth }).max() {
            month = latest
        } else {
            return nil
        }
        guard let current = months[month], let currentDaily = current.dailyAverage else { return nil }

        let lastYearMonth = addMonths(-12, to: month)
        if let last = months[lastYearMonth], let lastDaily = last.dailyAverage, lastDaily > 0 {
            return YearComparison(
                month: month,
                current: currentDaily,
                baseline: lastDaily,
                baselineKind: .sameMonthLastYear(lastYearMonth),
                currentRough: current.rough
            )
        }

        // No last year: the first three months of readings, leaving out the
        // month being compared so it is never compared with itself.
        guard let firstDay = series.keys.min() else { return nil }
        let windowEnd = min(addMonths(3, to: firstDay), month)
        let baselineDays = series.values.filter { $0.day >= firstDay && $0.day < windowEnd }
        guard !baselineDays.isEmpty else { return nil }
        let baseline = baselineDays.reduce(0) { $0 + $1.total } / Double(baselineDays.count)
        guard baseline > 0 else { return nil }
        let lastBaselineDay = baselineDays.map(\.day).max() ?? firstDay
        return YearComparison(
            month: month,
            current: currentDaily,
            baseline: baseline,
            baselineKind: .firstMonths(from: firstDay, to: lastBaselineDay),
            currentRough: current.rough
        )
    }

    // MARK: Usual rate

    /// Median daily rate of the last few intervals before `date`.
    static func usualDailyRate(meter: Meter, register: Register, readings: [Reading], before date: Date) -> Double? {
        let rates = intervals(meter: meter, register: register, readings: readings)
            .filter { $0.endDay <= day(date) }
            .suffix(6)
            .map(\.dailyRate)
            .sorted()
        guard !rates.isEmpty else { return nil }
        let mid = rates.count / 2
        return rates.count.isMultiple(of: 2) ? (rates[mid - 1] + rates[mid]) / 2 : rates[mid]
    }

    /// Latest interval's daily rate across all registers of a meter.
    static func latestDailyRate(meter: Meter, readings: [Reading]) -> (rate: Double, since: Date, days: Int, rough: Bool)? {
        let byRegister = intervals(meter: meter, readings: readings)
        var total = 0.0
        var since: Date?
        var days = 0
        var rough = false
        for register in meter.registers {
            guard let last = byRegister[register]?.last else { return nil }
            total += last.dailyRate
            since = since.map { min($0, last.startDay) } ?? last.startDay
            days = max(days, last.days)
            rough = rough || last.isRough
        }
        guard let since else { return nil }
        return (total, since, days, rough)
    }
}
