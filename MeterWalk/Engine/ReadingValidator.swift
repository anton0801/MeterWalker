//
//  ReadingValidator.swift
//  MeterWalk
//
//  Checks a new reading against the ones around it before it is saved.
//  A lower reading needs a reason; a big jump needs the user to say it is real.
//

import Foundation

enum ReadingIssue: Equatable {
    /// More digits than the dial has.
    case exceedsDial(maximum: Double)
    /// Lower than the previous counted reading. Needs a `DropReason`.
    case lowerThanPrevious(previous: Reading)
    /// Higher than a reading taken later. The date or the number is wrong.
    case higherThanLater(later: Reading)
    /// Another counted reading exists on the same day. Saving sets it aside.
    case sameDay(existing: Reading)
    /// Far above the usual daily use. Needs the user to confirm it is real.
    case unusual(ratio: Double, usualDaily: Double, newDaily: Double)
    /// A roll-over was chosen but the numbers do not fit one.
    case rolloverImplausible
}

struct ReadingDraft: Equatable {
    var meterID: UUID
    var register: Register
    var date: Date
    var value: Double
    var dropReason: DropReason?
    var acknowledgedUnusual = false
    var acknowledgedSameDay = false
}

enum ReadingValidator {
    static let unusualRatio = 3.0

    /// The first issue that stops the draft from being saved, or nil when it
    /// can be saved as it is. `excluding` lists readings about to be set aside.
    static func firstIssue(
        for draft: ReadingDraft,
        meter: Meter,
        readings: [Reading],
        excluding: Set<UUID> = [],
        replacing: UUID? = nil
    ) -> ReadingIssue? {
        if draft.value > meter.maximumValue + 1e-9 {
            return .exceedsDial(maximum: meter.maximumValue)
        }

        let others = readings.filter {
            $0.meterID == draft.meterID && $0.register == draft.register
                && !$0.isSetAside && !excluding.contains($0.id) && $0.id != replacing
        }
        let draftDay = ConsumptionEngine.day(draft.date)

        if !draft.acknowledgedSameDay,
           let existing = others.first(where: { ConsumptionEngine.day($0.date) == draftDay }) {
            return .sameDay(existing: existing)
        }

        let sameDayIDs = draft.acknowledgedSameDay
            ? Set(others.filter { ConsumptionEngine.day($0.date) == draftDay }.map(\.id))
            : []
        let counted = others.filter { !sameDayIDs.contains($0.id) }

        let previous = counted
            .filter { ConsumptionEngine.day($0.date) < draftDay }
            .max { $0.date < $1.date }
        let later = counted
            .filter { ConsumptionEngine.day($0.date) > draftDay }
            .min { $0.date < $1.date }

        if let previous, draft.value < previous.value - 1e-9 {
            switch draft.dropReason {
            case nil:
                return .lowerThanPrevious(previous: previous)
            case .rolledOver?:
                // A roll-over only makes sense when the old reading was high on
                // the dial and the new one is low.
                if previous.value < meter.rolloverValue * 0.5 || draft.value > meter.rolloverValue * 0.5 {
                    return .rolloverImplausible
                }
            case .meterReplaced?, .typo?:
                break
            }
        }

        if let later, draft.value > later.value + 1e-9, later.dropReason == nil {
            return .higherThanLater(later: later)
        }

        if !draft.acknowledgedUnusual,
           let previous,
           draft.dropReason != .meterReplaced {
            let days = ConsumptionEngine.daysBetween(previous.date, draft.date)
            if days > 0 {
                var use = draft.value - previous.value
                if draft.dropReason == .rolledOver {
                    use = meter.rolloverValue - previous.value + draft.value
                }
                let newDaily = use / Double(days)
                let pool = readings.filter { !excluding.contains($0.id) && $0.id != replacing }
                if let usual = ConsumptionEngine.usualDailyRate(meter: meter, register: draft.register, readings: pool, before: previous.date),
                   usual > 0 {
                    let ratio = newDaily / usual
                    if ratio >= unusualRatio {
                        return .unusual(ratio: ratio, usualDaily: usual, newDaily: newDaily)
                    }
                }
            }
        }

        return nil
    }

    /// The counted reading just before a date, for showing context.
    static func previousReading(meterID: UUID, register: Register, before date: Date, readings: [Reading], excluding: Set<UUID> = []) -> Reading? {
        readings
            .filter {
                $0.meterID == meterID && $0.register == register && !$0.isSetAside
                    && !excluding.contains($0.id)
                    && ConsumptionEngine.day($0.date) < ConsumptionEngine.day(date)
            }
            .max { $0.date < $1.date }
    }
}
