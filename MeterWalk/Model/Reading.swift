//
//  Reading.swift
//  MeterWalk
//
//  One number read off one register on one date, with the photo that proves it.
//

import Foundation

enum ReadingSource: String, Codable {
    /// The camera read the number and the user confirmed it.
    case recognized
    /// A photo was taken but the user typed the number.
    case typedWithPhoto
    /// Typed with no photo.
    case typed

    var title: String {
        switch self {
        case .recognized: return "Read from photo, confirmed"
        case .typedWithPhoto: return "Typed, photo attached"
        case .typed: return "Typed, no photo"
        }
    }
}

/// Why a reading is lower than the one before it. A lower reading is never
/// saved without one of these.
enum DropReason: String, Codable, CaseIterable, Identifiable {
    case meterReplaced
    case typo
    case rolledOver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meterReplaced: return "Meter Replaced"
        case .typo: return "Typo"
        case .rolledOver: return "Meter Rolled Over"
        }
    }

    var explanation: String {
        switch self {
        case .meterReplaced:
            return "A new meter starts counting from this reading. No use is worked out across the swap."
        case .typo:
            return "The earlier reading was mistyped. It is set aside and left out of every calculation, and its photo is kept."
        case .rolledOver:
            return "The dial passed its highest number and started again from zero."
        }
    }
}

struct Reading: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var meterID: UUID
    var register: Register
    var date: Date
    var value: Double
    var photoFile: String?
    var source: ReadingSource
    /// Set when this reading is lower than the previous one.
    var dropReason: DropReason?
    /// Readings set aside (a typo, or replaced by a later reading the same
    /// day) stay in the history with their photo but are left out of sums.
    var isSetAside = false
    var setAsideNote: String?
    /// When the jump was far above usual use and the user said it was real.
    var confirmedUnusualRatio: Double?
    var note: String = ""
    var createdAt = Date()
}
