//
//  Formatting.swift
//  MeterWalk
//
//  Numbers, money and dates as the app prints them.
//

import Foundation

enum NumberText {
    private static func formatter(min: Int, max: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = "\u{2009}"
        f.minimumFractionDigits = min
        f.maximumFractionDigits = max
        return f
    }

    private static let plainFormatter = formatter(min: 0, max: 2)
    private static let oneFormatter = formatter(min: 1, max: 1)

    /// "1 184", "12.5".
    static func plain(_ value: Double) -> String {
        plainFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Always one decimal: "12.4".
    static func one(_ value: Double) -> String {
        oneFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Whole number: "139".
    static func whole(_ value: Double) -> String {
        formatter(min: 0, max: 0).string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
    }

    /// Use with sensible precision for its size.
    static func use(_ value: Double) -> String {
        abs(value) >= 100 ? whole(value) : one(value)
    }

    /// Daily rates: "12.4", or "0.35" for small water use.
    static func rate(_ value: Double) -> String {
        if abs(value) >= 10 { return one(value) }
        return formatter(min: 2, max: 2).string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func signedPercent(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
    }

    /// Parses what a person types, accepting a comma as the decimal mark and
    /// spaces as grouping.
    static func parse(_ text: String) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{2009}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !cleaned.isEmpty else { return nil }
        let commas = cleaned.filter { $0 == "," }.count
        let dots = cleaned.filter { $0 == "." }.count
        if commas == 1 && dots == 0 {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        } else if commas > 0 && dots == 1 {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        }
        return Double(cleaned)
    }

    /// A value ready for a text field, without grouping.
    static func editable(_ value: Double?) -> String {
        guard let value else { return "" }
        if value == value.rounded() { return String(Int(value)) }
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

struct MoneyText {
    let currencyCode: String

    private func formatter(fraction: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.minimumFractionDigits = fraction
        f.maximumFractionDigits = fraction
        return f
    }

    /// Totals: whole units once they reach 100 ("€1,184"), cents below.
    func total(_ value: Double) -> String {
        let fraction = abs(value) >= 100 ? 0 : 2
        return formatter(fraction: fraction).string(from: NSNumber(value: value)) ?? NumberText.plain(value)
    }

    /// Prices per unit keep up to four decimals: "€0.2451".
    func rate(_ value: Double) -> String {
        let f = formatter(fraction: 2)
        f.maximumFractionDigits = 4
        return f.string(from: NSNumber(value: value)) ?? NumberText.plain(value)
    }

    func exact(_ value: Double) -> String {
        formatter(fraction: 2).string(from: NSNumber(value: value)) ?? NumberText.plain(value)
    }

    var symbol: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        return f.currencySymbol ?? currencyCode
    }
}

enum DateText {
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let dayMonth = formatter("d MMM")
    private static let dayMonthYear = formatter("d MMM yyyy")
    private static let monthName = formatter("MMMM")
    private static let monthYear = formatter("MMMM yyyy")
    private static let shortMonth = formatter("MMM")
    private static let time = formatter("HH:mm")

    /// "12 Aug", with the year when it is not this year.
    static func short(_ date: Date, now: Date = Date()) -> String {
        let cal = ConsumptionEngine.calendar
        return cal.component(.year, from: date) == cal.component(.year, from: now)
            ? dayMonth.string(from: date)
            : dayMonthYear.string(from: date)
    }

    static func full(_ date: Date) -> String { dayMonthYear.string(from: date) }
    static func month(_ date: Date) -> String { monthName.string(from: date) }
    static func monthAndYear(_ date: Date) -> String { monthYear.string(from: date) }
    static func monthLetter(_ date: Date) -> String { String(shortMonth.string(from: date).prefix(1)) }
    static func monthShort(_ date: Date) -> String { shortMonth.string(from: date) }
    static func clock(_ date: Date) -> String { time.string(from: date) }

    static func minutes(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
}
