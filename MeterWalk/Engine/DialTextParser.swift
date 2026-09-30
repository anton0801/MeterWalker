//
//  DialTextParser.swift
//  MeterWalk
//
//  Turns text read off a meter face into a number that fits the dial's
//  layout. Kept free of UIKit and Vision so it can be tested on its own.
//

import Foundation

struct RecognizedReading: Equatable {
    let value: Double
    /// As the dial shows it, with leading zeros: "04182.6".
    let text: String
    let confidence: Float
}

enum DialTextParser {
    /// Letters Vision often returns for drum digits.
    static let lookalikes: [Character: Character] = [
        "O": "0", "o": "0", "D": "0", "Q": "0",
        "I": "1", "l": "1", "i": "1", "|": "1",
        "Z": "2", "z": "2",
        "S": "5", "s": "5",
        "G": "6",
        "B": "8",
    ]

    /// Turns raw text into a reading that fits the dial layout.
    /// Returns whether all fraction digits were present.
    static func interpret(_ raw: String, digitsBefore: Int, digitsAfter: Int, confidence: Float = 1) -> (RecognizedReading, Bool)? {
        // Words such as "kWh" or a maker's name are not the counter.
        let strayLetters = raw.filter { $0.isLetter && lookalikes[$0] == nil }
        guard strayLetters.count <= 1 else { return nil }
        let mapped = String(raw.map { lookalikes[$0] ?? $0 })
        let kept = mapped.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == " " }
        let digitsOnly = kept.filter(\.isNumber)
        guard digitsOnly.count >= max(1, digitsBefore - 1) else { return nil }
        // Anything much longer than the dial is a serial number or a date.
        guard digitsOnly.count <= digitsBefore + digitsAfter else { return nil }

        var whole: String
        var fraction: String
        let separators = kept.split(whereSeparator: { $0 == "." || $0 == "," || $0 == " " }).map(String.init).filter { !$0.isEmpty }

        if separators.count == 2, separators[0].count <= digitsBefore, separators[1].count <= digitsAfter, digitsAfter > 0 {
            whole = separators[0]
            fraction = separators[1]
        } else if digitsOnly.count == digitsBefore + digitsAfter {
            whole = String(digitsOnly.prefix(digitsBefore))
            fraction = String(digitsOnly.suffix(digitsAfter))
        } else if digitsOnly.count <= digitsBefore {
            // The fraction drum was not read; keep the whole number.
            whole = digitsOnly
            fraction = ""
        } else {
            whole = String(digitsOnly.prefix(digitsBefore))
            fraction = String(digitsOnly.dropFirst(digitsBefore))
        }

        let exact = fraction.count == digitsAfter && whole.count == digitsBefore
        fraction = String(fraction.prefix(digitsAfter))
        let padded = fraction.padding(toLength: digitsAfter, withPad: "0", startingAt: 0)
        let valueText = digitsAfter > 0 ? "\(whole).\(padded)" : whole
        guard let value = Double(valueText) else { return nil }
        let display = MeterFormat.dialText(value, before: digitsBefore, after: digitsAfter)
        return (RecognizedReading(value: value, text: display, confidence: confidence), exact)
    }
}
