import Foundation
import UIKit
import UserNotifications

/// The user's own meter value on a given date and how it was found.
struct OwnValue: Equatable {
    enum Method: Equatable {
        /// A photo taken that very day.
        case photo(Reading)
        /// Between two photos, at the daily rate between them.
        case interpolated(Reading, Reading)
        /// Past the nearest photo, at the latest daily rate. Only within 45 days.
        case extrapolated(Reading, days: Int)
    }

    let value: Double
    let method: Method

    var readingsUsed: [Reading] {
        switch method {
        case .photo(let r): return [r]
        case .interpolated(let a, let b): return [a, b]
        case .extrapolated(let r, _): return [r]
        }
    }
}

final class Buzzer: Chime {
    func ring() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }
}


struct RegisterCheck: Equatable, Identifiable {
    var id: Register { register }
    let register: Register
    let billOpening: Double?
    let billClosing: Double?
    let ownOpening: OwnValue?
    let ownClosing: OwnValue?

    var closingDifference: Double? {
        guard let billClosing, let ownClosing else { return nil }
        return billClosing - ownClosing.value
    }

    var openingDifference: Double? {
        guard let billOpening, let ownOpening else { return nil }
        return billOpening - ownOpening.value
    }

    var billedUse: Double? {
        guard let billOpening, let billClosing else { return nil }
        return billClosing - billOpening
    }

    var ownUse: Double? {
        guard let ownOpening, let ownClosing else { return nil }
        return ownClosing.value - ownOpening.value
    }

    /// Units billed beyond what the meter shows. Uses billed-versus-own use
    /// when both ends are known, otherwise the closing gap alone.
    var excessUnits: Double? {
        if let billedUse, let ownUse { return billedUse - ownUse }
        return closingDifference
    }
}

struct BillCheckResult: Equatable {
    enum Status: Equatable {
        case noMeter
        case noBillReadings
        case notEnoughReadings
        case matches
        case overbilled
        case underbilled
    }

    let status: Status
    let checks: [RegisterCheck]
    let excessUnits: Double?
    let rate: Double?
    let rateSource: String?

    var excessMoney: Double? {
        guard let excessUnits, let rate, excessUnits > 0 else { return nil }
        return excessUnits * rate
    }
}

enum BillCheckEngine {
    static let extrapolationLimitDays = 45

    static func ownValue(at date: Date, meter: MeterItem, register: Register, readings: [Reading]) -> OwnValue? {
        let target = ConsumptionEngine.day(date)
        let counted = ConsumptionEngine.countedReadings(readings, meterID: meter.id, register: register)
        if let exact = counted.first(where: { ConsumptionEngine.day($0.date) == target }) {
            return OwnValue(value: exact.value, method: .photo(exact))
        }

        let intervals = ConsumptionEngine.intervals(meter: meter, register: register, readings: readings)
        if let interval = intervals.first(where: { $0.startDay < target && target < $0.endDay }),
           let start = counted.first(where: { $0.id == interval.startReadingID }),
           let end = counted.first(where: { $0.id == interval.endReadingID }) {
            let offset = Double(ConsumptionEngine.daysBetween(interval.startDay, target))
            var value = interval.startValue + interval.dailyRate * offset
            if interval.rolledOver, value >= meter.rolloverValue {
                value -= meter.rolloverValue
            }
            return OwnValue(value: value, method: .interpolated(start, end))
        }

        // Outside the photos: extrapolate from the nearest end, but only a
        // short way and only when a daily rate exists.
        if let last = intervals.last, target > last.endDay,
           let lastReading = counted.first(where: { $0.id == last.endReadingID }) {
            let days = ConsumptionEngine.daysBetween(last.endDay, target)
            guard days <= extrapolationLimitDays else { return nil }
            let value = last.endValue + last.dailyRate * Double(days)
            return OwnValue(value: value, method: .extrapolated(lastReading, days: days))
        }
        if let first = intervals.first, target < first.startDay,
           let firstReading = counted.first(where: { $0.id == first.startReadingID }) {
            let days = ConsumptionEngine.daysBetween(target, first.startDay)
            guard days <= extrapolationLimitDays else { return nil }
            let value = max(0, first.startValue - first.dailyRate * Double(days))
            return OwnValue(value: value, method: .extrapolated(firstReading, days: -days))
        }
        return nil
    }

    static func check(bill: Bill, meter: MeterItem?, readings: [Reading], currentTariff: TariffItem?) -> BillCheckResult {
        guard let meter else {
            return BillCheckResult(status: .noMeter, checks: [], excessUnits: nil, rate: nil, rateSource: nil)
        }
        guard bill.hasAnyReading else {
            return BillCheckResult(status: .noBillReadings, checks: [], excessUnits: nil, rate: nil, rateSource: nil)
        }

        var checks: [RegisterCheck] = []
        for register in meter.registers {
            guard let billReadings = bill.readings(for: register),
                  billReadings.opening != nil || billReadings.closing != nil else { continue }
            checks.append(RegisterCheck(
                register: register,
                billOpening: billReadings.opening,
                billClosing: billReadings.closing,
                ownOpening: billReadings.opening == nil ? nil : ownValue(at: bill.periodFrom, meter: meter, register: register, readings: readings),
                ownClosing: billReadings.closing == nil ? nil : ownValue(at: bill.periodTo, meter: meter, register: register, readings: readings)
            ))
        }

        let comparable = checks.filter { $0.excessUnits != nil }
        guard !comparable.isEmpty else {
            return BillCheckResult(status: .notEnoughReadings, checks: checks, excessUnits: nil, rate: nil, rateSource: nil)
        }

        let excess = comparable.reduce(0) { $0 + ($1.excessUnits ?? 0) }
        let ownUse = comparable.compactMap(\.ownUse).reduce(0, +)
        let tolerance = max(abs(ownUse) * 0.01, meter.utility == .electricity ? 1 : 0.1)

        let status: BillCheckResult.Status
        if abs(excess) <= tolerance {
            status = .matches
        } else {
            status = excess > 0 ? .overbilled : .underbilled
        }

        let (rate, source) = unitRate(for: comparable, meter: meter, bill: bill, currentTariff: currentTariff)
        return BillCheckResult(status: status, checks: checks, excessUnits: excess, rate: rate, rateSource: source)
    }

    /// The price used to turn extra units into money, and where it came from.
    static func unitRate(for checks: [RegisterCheck], meter: MeterItem, bill: Bill, currentTariff: TariffItem?) -> (Double?, String?) {
        if let tariff = currentTariff {
            switch tariff.structure {
            case .flat:
                return (tariff.unitRate, "at the unit rate of your current tariff, \(tariff.displayName)")
            case .twoRate:
                if meter.kind.isTwoRate {
                    // Weight by where the extra units are.
                    let day = checks.first { $0.register == .day }?.excessUnits ?? 0
                    let night = checks.first { $0.register == .night }?.excessUnits ?? 0
                    let total = day + night
                    if total != 0 {
                        let blended = (day * tariff.dayRate + night * tariff.nightRate) / total
                        return (blended, "at the day and night rates of your current tariff, \(tariff.displayName)")
                    }
                    return (tariff.dayRate, "at the day rate of your current tariff, \(tariff.displayName)")
                }
                if let share = meter.nightShareAssumption {
                    let blended = tariff.dayRate * (1 - share) + tariff.nightRate * share
                    return (blended, "at your current tariff's rates, assuming \(Int((share * 100).rounded()))% night use as you set it")
                }
                return (tariff.dayRate, "at the day rate of your current tariff, \(tariff.displayName)")
            case .tiered:
                let tiers = tariff.sortedTiers
                let billedUse = checks.compactMap(\.billedUse).reduce(0, +)
                let billDays = max(1, ConsumptionEngine.daysBetween(bill.periodFrom, bill.periodTo))
                let monthly = billedUse * 30.44 / Double(billDays)
                if let tier = tiers.first(where: { ($0.upTo ?? .infinity) >= monthly }) ?? tiers.last {
                    return (tier.rate, "at the step of your current tariff this bill's use falls in")
                }
            }
        }
        let billedUse = checks.compactMap(\.billedUse).reduce(0, +)
        if billedUse > 0, bill.amount > 0 {
            return (bill.amount / billedUse, "at the bill's average price (amount ÷ billed use, standing charge included)")
        }
        return (nil, nil)
    }
}
