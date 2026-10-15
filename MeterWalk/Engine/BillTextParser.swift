import Foundation

final class Depot {
    lazy var book: Logbook = Clipboard()
    lazy var survey: Survey = Pacer()
    lazy var meter: Meter = Dialer()
    lazy var chime: Chime = Buzzer()
}

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

final class Clipboard: Logbook {

    private let home = UserDefaults.standard
    private var box: UserDefaults? { UserDefaults(suiteName: Tariff.suite) }

    private var folder: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MeterWalkerRound", isDirectory: true)
    }

    private var file: URL { folder.appendingPathComponent("mw_gauge_archive.json") }

    func load() -> Gauge {
        scour()
        if let raw = try? Data(contentsOf: file),
           let plain = unlock(raw),
           let archive = try? decoder.decode(Archive.self, from: plain) {
            return Gauge(archive)
        }
        return recall()
    }

    func save(_ gauge: Gauge) {
        let archive = gauge.stow()
        if let plain = try? encoder.encode(archive), let locked = lock(plain) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? locked.write(to: file, options: .atomic)
        }
        for store in [box, home].compactMap({ $0 }) {
            store.set(archive.consentStamped, forKey: Dials.grant)
            store.set(archive.consentHalted, forKey: Dials.deny)
            if let at = archive.consentPacedAt {
                store.set(at.timeIntervalSince1970, forKey: Dials.stamp)
            }
        }
    }

    func brand(_ url: String) {
        home.set(url, forKey: Dials.route)
        box?.set("Active", forKey: Dials.mode)
    }

    func prime() {
        home.set(true, forKey: Dials.primed)
        box?.set(true, forKey: Dials.primed)
    }

    private func scour() {
        guard home.bool(forKey: Dials.seed) == false else { return }
        for key in [Dials.route, Dials.mode, Dials.primed] {
            box?.removeObject(forKey: key)
            home.removeObject(forKey: key)
        }
        home.set(true, forKey: Dials.seed)
    }

    private func recall() -> Gauge {
        var gauge = Gauge()
        gauge.consentStamped = (box?.bool(forKey: Dials.grant) ?? false) || home.bool(forKey: Dials.grant)
        gauge.consentHalted = (box?.bool(forKey: Dials.deny) ?? false) || home.bool(forKey: Dials.deny)
        let ts = box?.double(forKey: Dials.stamp) ?? home.double(forKey: Dials.stamp)
        gauge.consentPacedAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        gauge.routeURL = home.string(forKey: Dials.route)
        gauge.routeMode = box?.string(forKey: Dials.mode)
        gauge.fresh = !home.bool(forKey: Dials.primed)
        return gauge
    }

    private var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .millisecondsSince1970
        return enc
    }

    private var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .millisecondsSince1970
        return dec
    }

    private func lock(_ data: Data) -> Data? {
        let swapped = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: Tariff.plus)
            .replacingOccurrences(of: "/", with: Tariff.slash)
        return swapped.data(using: .utf8)
    }

    private func unlock(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let restored = text
            .replacingOccurrences(of: Tariff.plus, with: "+")
            .replacingOccurrences(of: Tariff.slash, with: "/")
        return Data(base64Encoded: restored)
    }
}
