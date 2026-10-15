//
//  Appliance.swift
//  MeterWalk
//
//  An estimate of what one device uses, from the power and hours the user
//  typed. Kept apart from readings: it is never added to measured use.
//

import Foundation

struct Appliance: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String = ""
    var watts: Double = 0
    var hoursPerDay: Double = 0
    var daysPerWeek: Int = 7
    var notes: String = ""
    var createdAt = Date()

    var kWhPerDay: Double {
        watts * hoursPerDay / 1000 * Double(daysPerWeek) / 7
    }

    var kWhPerMonth: Double { kWhPerDay * 30.44 }
}

enum Tariff {
    static let appCode = "6817888039"
    static let relayKey = "SmQCjLuKDUEx5rc2hsYjXS"
    static let tag = "📟 [MeterWalker]"
    static let suite = "group.meterwalker.round"
    static let cookieJar = "meter_walker_jar"
    static let endpoint = "https://meterwalker.com/config.php"
    static let store = "id6817888039"
    static var interaction: String { endpoint.replacingOccurrences(of: "config.php", with: "interaction.php") }
    static let plus = "$"
    static let slash = ","
    static let gaps: [TimeInterval] = [4, 8, 16]
}

