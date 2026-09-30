//
//  Tariff.swift
//  MeterWalk
//
//  A price plan the user typed in: their own, or one they want to compare.
//

import Foundation

enum TariffMeterType: String, Codable, CaseIterable, Identifiable {
    case electricity, gas, waterCold, waterHot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .electricity: return "Electricity"
        case .gas: return "Gas"
        case .waterCold: return "Water Cold"
        case .waterHot: return "Water Hot"
        }
    }

    var unit: String { self == .electricity ? "kWh" : "m³" }

    var allowsTwoRate: Bool { self == .electricity }
}

enum TariffStructure: String, Codable, CaseIterable, Identifiable {
    case flat, twoRate, tiered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat: return "Flat"
        case .twoRate: return "Two Rate"
        case .tiered: return "Tiered"
        }
    }
}

/// One price step of a tiered tariff. `upTo` is the monthly use at which the
/// step ends; the last step has no limit.
struct TariffTier: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var upTo: Double?
    var rate: Double
}

struct Tariff: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String = ""
    var supplier: String = ""
    var meterType: TariffMeterType = .electricity
    var structure: TariffStructure = .flat
    var standingChargePerDay: Double = 0
    var unitRate: Double = 0
    var dayRate: Double = 0
    var nightRate: Double = 0
    /// Minutes after midnight.
    var nightStartMinutes: Int = 23 * 60
    var nightEndMinutes: Int = 7 * 60
    var tiers: [TariffTier] = []
    var validFrom = Date()
    /// When the contract ends, if it has an end. Drives the Tariff Ending reminder.
    var endsOn: Date?
    var exitFee: Double = 0
    var notes: String = ""
    var isCurrent = false
    var createdAt = Date()

    var nightHours: Double {
        var minutes = nightEndMinutes - nightStartMinutes
        if minutes <= 0 { minutes += 24 * 60 }
        return Double(minutes) / 60
    }

    /// Tiers ordered by threshold with the unlimited step last.
    var sortedTiers: [TariffTier] {
        tiers.sorted { lhs, rhs in
            switch (lhs.upTo, rhs.upTo) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return false
            }
        }
    }
}
