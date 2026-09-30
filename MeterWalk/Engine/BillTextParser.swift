//
//  BillTextParser.swift
//  MeterWalk
//
//  Finds the amount and the billing period in lines of text read off a
//  bill. Free of UIKit and Vision so it can be tested on its own.
//

import Foundation

struct RecognizedBill: Equatable {
    var amount: Double?
    var periodFrom: Date?
    var periodTo: Date?

    var isEmpty: Bool { amount == nil && periodFrom == nil && periodTo == nil }
}

enum BillTextParser {
    static let totalWords = [
        "total", "amount due", "to pay", "balance", "due", "payable", "charges",
        "итого", "к оплате", "сумма", "всего",
    ]

    static func parse(lines: [String]) -> RecognizedBill {
        var result = RecognizedBill()
        result.amount = amount(in: lines)
        let (from, to) = period(in: lines)
        result.periodFrom = from
        result.periodTo = to
        return result
    }

    // MARK: Amount

    private static let amountPattern = try! NSRegularExpression(
        pattern: #"(?<![\d.,])(\d{1,3}(?:[  .,]\d{3})*|\d+)([.,]\d{2})(?![\d])"#
    )

    static func amounts(in line: String) -> [Double] {
        let range = NSRange(line.startIndex..., in: line)
        return amountPattern.matches(in: line, range: range).compactMap { match in
            guard let r = Range(match.range, in: line) else { return nil }
            return NumberText.parse(String(line[r]).replacingOccurrences(of: "\u{00A0}", with: ""))
        }
    }

    static func amount(in lines: [String]) -> Double? {
        // Prefer an amount on, or just after, a line that names the total.
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard totalWords.contains(where: { lower.contains($0) }) else { continue }
            if let value = amounts(in: line).last { return value }
            if index + 1 < lines.count, let value = amounts(in: lines[index + 1]).first { return value }
        }
        return lines.flatMap(amounts(in:)).max()
    }

    // MARK: Period

    static func period(in lines: [String]) -> (Date?, Date?) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return (nil, nil)
        }
        func dates(_ text: String) -> [Date] {
            detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.date)
        }
        // "01/07/2026 – 03/08/2026" can come back as one match with a duration.
        for line in lines {
            for match in detector.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let start = match.date, match.duration >= 24 * 3600 {
                    return (start, start.addingTimeInterval(match.duration))
                }
            }
        }
        // A line with two dates is most likely the billing period.
        for line in lines {
            let found = dates(line)
            if found.count >= 2 {
                let sorted = found.sorted()
                return (sorted.first, sorted.last)
            }
        }
        // Otherwise the two dates on lines that mention a period.
        let periodWords = ["period", "from", "to", "billing", "период", "с ", "по "]
        let flagged = lines.filter { line in periodWords.contains { line.lowercased().contains($0) } }.flatMap(dates)
        if flagged.count >= 2 {
            let sorted = flagged.sorted()
            return (sorted.first, sorted.last)
        }
        return (nil, nil)
    }
}
