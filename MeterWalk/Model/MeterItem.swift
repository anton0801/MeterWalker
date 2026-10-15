//
//  Meter.swift
//  MeterWalk
//
//  A physical meter on the wall and how its dial is laid out. The number of
//  digits before and after the decimal point is what lets the camera tell the
//  whole part of a reading from the fraction.
//

import Foundation

enum Utility: String, Codable, CaseIterable, Identifiable {
    case electricity, gas, water

    var id: String { rawValue }
}

enum MeterKind: String, Codable, CaseIterable, Identifiable {
    case electricitySingle
    case electricityTwoRate
    case gas
    case waterCold
    case waterHot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .electricitySingle: return "Electricity Single Rate"
        case .electricityTwoRate: return "Electricity Two Rate"
        case .gas: return "Gas"
        case .waterCold: return "Water Cold"
        case .waterHot: return "Water Hot"
        }
    }

    /// The name a new meter of this kind gets until the user renames it.
    var defaultName: String {
        switch self {
        case .electricitySingle, .electricityTwoRate: return "Electricity"
        case .gas: return "Gas"
        case .waterCold: return "Cold Water"
        case .waterHot: return "Hot Water"
        }
    }

    var utility: Utility {
        switch self {
        case .electricitySingle, .electricityTwoRate: return .electricity
        case .gas: return .gas
        case .waterCold, .waterHot: return .water
        }
    }

    var tariffType: TariffMeterType {
        switch self {
        case .electricitySingle, .electricityTwoRate: return .electricity
        case .gas: return .gas
        case .waterCold: return .waterCold
        case .waterHot: return .waterHot
        }
    }

    var defaultUnit: String {
        utility == .electricity ? "kWh" : "m³"
    }

    var defaultDigitsBefore: Int { 5 }

    var defaultDigitsAfter: Int {
        utility == .electricity ? 1 : 3
    }

    var registers: [Register] {
        self == .electricityTwoRate ? [.day, .night] : [.total]
    }

    var isTwoRate: Bool { self == .electricityTwoRate }
}

/// One counter on a meter. Single-rate meters have one; two-rate electricity
/// meters keep day and night apart.
enum Register: String, Codable, CaseIterable, Identifiable {
    case total, day, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .total: return "Total"
        case .day: return "Day"
        case .night: return "Night"
        }
    }

    /// Label printed on most two-rate meters next to the register.
    var meterLabel: String {
        switch self {
        case .total: return ""
        case .day: return "T1"
        case .night: return "T2"
        }
    }
}

struct MeterItem: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var kind: MeterKind
    var unit: String
    var serialNumber: String = ""
    var digitsBeforeDecimal: Int
    var digitsAfterDecimal: Int
    var location: String = ""
    var supplier: String = ""
    var photoFile: String?
    var notes: String = ""
    var createdAt = Date()
    /// Share of use at night that the user set for comparing this single-rate
    /// meter with two-rate tariffs. The app never guesses this.
    var nightShareAssumption: Double?

    init(kind: MeterKind, name: String? = nil) {
        self.kind = kind
        self.name = name ?? kind.defaultName
        self.unit = kind.defaultUnit
        self.digitsBeforeDecimal = kind.defaultDigitsBefore
        self.digitsAfterDecimal = kind.defaultDigitsAfter
    }

    var registers: [Register] { kind.registers }
    var utility: Utility { kind.utility }

    /// The value at which the dial wraps back to zero.
    var rolloverValue: Double { pow(10, Double(digitsBeforeDecimal)) }

    /// The largest number this dial can show.
    var maximumValue: Double {
        rolloverValue - pow(10, -Double(digitsAfterDecimal))
    }

    /// A reading laid out exactly as the dial shows it, with leading zeros.
    func dialText(_ value: Double) -> String {
        MeterFormat.dialText(value, before: digitsBeforeDecimal, after: digitsAfterDecimal)
    }

    /// The unlit segments behind a reading: "88888.8".
    var ghostText: String {
        MeterFormat.ghostText(before: digitsBeforeDecimal, after: digitsAfterDecimal)
    }
}

enum MeterFormat {
    static func dialText(_ value: Double, before: Int, after: Int) -> String {
        let clamped = max(0, value)
        let width = before + (after > 0 ? after + 1 : 0)
        let text = String(format: "%0\(width).\(after)f", clamped)
        // A value too big for the dial is shown as it is rather than cut.
        return text
    }

    static func ghostText(before: Int, after: Int) -> String {
        String(repeating: "8", count: before) + (after > 0 ? "." + String(repeating: "8", count: after) : "")
    }
}

enum Fault: Error {
    case snapped
    case void404
    case denied
    case cooldown(TimeInterval)
    case scrambled

    var sealed: Bool {
        switch self {
        case .void404, .denied: return true
        default: return false
        }
    }

    var cool: TimeInterval? {
        if case .cooldown(let seconds) = self { return seconds }
        return nil
    }
}
