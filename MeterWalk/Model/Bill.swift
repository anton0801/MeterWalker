//
//  Bill.swift
//  MeterWalk
//
//  What the supplier charged, and the readings they say they used.
//

import Foundation

enum BillReadingType: String, Codable, CaseIterable, Identifiable {
    case actual, estimated, customer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actual: return "Actual"
        case .estimated: return "Estimated"
        case .customer: return "Customer"
        }
    }

    var explanation: String {
        switch self {
        case .actual: return "The supplier read the meter."
        case .estimated: return "The supplier guessed the reading."
        case .customer: return "You sent the reading in."
        }
    }
}

struct BillRegisterReadings: Codable, Equatable, Hashable {
    var register: Register
    var opening: Double?
    var closing: Double?
}

struct Bill: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var meterID: UUID?
    var supplier: String = ""
    var periodFrom: Date
    var periodTo: Date
    var readings: [BillRegisterReadings] = []
    var readingType: BillReadingType = .estimated
    var amount: Double = 0
    var photoFile: String?
    var notes: String = ""
    var createdAt = Date()

    func readings(for register: Register) -> BillRegisterReadings? {
        readings.first { $0.register == register }
    }

    var hasAnyReading: Bool {
        readings.contains { $0.opening != nil || $0.closing != nil }
    }
}

enum Dials {
    static let pushURL = "temp_url"
    static let fcm = "fcm_token"
    static let push = "push_token"
    static let sharedFcm = "shared_fcm"
    static let att = "mw_att_status"
    static let primed = "mw_primed"
    static let route = "mw_route_url"
    static let mode = "mw_route_mode"
    static let grant = "mw_consent_locked"
    static let deny = "mw_consent_drifted"
    static let stamp = "mw_consent_mapped_at"
    static let blob = "mw_gauge_blob"
    static let seed = "mw_seed"
}
