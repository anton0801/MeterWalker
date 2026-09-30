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
