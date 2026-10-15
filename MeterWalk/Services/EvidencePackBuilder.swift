//
//  EvidencePackBuilder.swift
//  MeterWalk
//
//  A PDF to send a supplier: the bill, the user's dated meter photos, and the
//  calculation. It states facts only; it does not write a complaint.
//

import UIKit

enum EvidencePackBuilder {
    static func build(
        bill: Bill,
        meter: MeterItem,
        result: BillCheckResult,
        photos: PhotoStore,
        money: MoneyText
    ) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 in points
        let margin: CGFloat = 44
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: {
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [
                kCGPDFContextTitle as String: "Meter reading evidence — \(meter.name)",
                kCGPDFContextCreator as String: "Meter Walk",
            ]
            return format
        }())

        let title = UIFont.systemFont(ofSize: 20, weight: .bold)
        let heading = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let body = UIFont.systemFont(ofSize: 11)
        let mono = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let dark = UIColor(red: 0.04, green: 0.10, blue: 0.20, alpha: 1)
        let grey = UIColor(white: 0.35, alpha: 1)

        let data = renderer.pdfData { context in
            var y: CGFloat = margin

            func newPage() {
                context.beginPage()
                y = margin
            }

            func ensure(_ height: CGFloat) {
                if y + height > page.height - margin { newPage() }
            }

            @discardableResult
            func text(_ string: String, font: UIFont, color: UIColor? = nil, spacingAfter: CGFloat = 6) -> CGFloat {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color ?? dark]
                let width = page.width - margin * 2
                let rect = (string as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes, context: nil
                )
                ensure(rect.height)
                (string as NSString).draw(
                    with: CGRect(x: margin, y: y, width: width, height: rect.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes, context: nil
                )
                y += ceil(rect.height) + spacingAfter
                return rect.height
            }

            func row(_ key: String, _ value: String) {
                text("\(key):  \(value)", font: mono, spacingAfter: 3)
            }

            func image(_ image: UIImage, caption: String, maxHeight: CGFloat = 300) {
                let width = page.width - margin * 2
                let aspect = image.size.height / max(1, image.size.width)
                var size = CGSize(width: width, height: width * aspect)
                if size.height > maxHeight {
                    size = CGSize(width: maxHeight / aspect, height: maxHeight)
                }
                ensure(size.height + 30)
                image.draw(in: CGRect(x: margin, y: y, width: size.width, height: size.height))
                y += size.height + 6
                text(caption, font: body, color: grey, spacingAfter: 16)
            }

            newPage()
            text("Meter reading evidence", font: title, spacingAfter: 4)
            text("Prepared with Meter Walk on \(DateText.full(Date())). Photos are the originals taken on the dates shown.", font: body, color: grey, spacingAfter: 16)

            text("Meter", font: heading)
            row("Name", meter.name)
            row("Type", meter.kind.title)
            if !meter.serialNumber.isEmpty { row("Serial number", meter.serialNumber) }
            if !meter.supplier.isEmpty { row("Supplier", meter.supplier) }
            if !meter.location.isEmpty { row("Location", meter.location) }
            y += 10

            text("Bill", font: heading)
            if !bill.supplier.isEmpty { row("Supplier", bill.supplier) }
            row("Period", "\(DateText.full(bill.periodFrom)) – \(DateText.full(bill.periodTo))")
            row("Reading type on bill", bill.readingType.title)
            row("Amount", money.exact(bill.amount))
            y += 10

            text("Comparison", font: heading)
            for check in result.checks {
                let prefix = check.register == .total ? "" : "\(check.register.title) register — "
                if let billClosing = check.billClosing {
                    row("\(prefix)Closing reading on bill (\(DateText.full(bill.periodTo)))", meter.dialText(billClosing))
                }
                if let own = check.ownClosing {
                    row("\(prefix)Own meter reading, same date", "\(meter.dialText(own.value))  \(methodText(own, meter: meter))")
                }
                if let billOpening = check.billOpening {
                    row("\(prefix)Opening reading on bill (\(DateText.full(bill.periodFrom)))", meter.dialText(billOpening))
                }
                if let own = check.ownOpening {
                    row("\(prefix)Own meter reading, same date", "\(meter.dialText(own.value))  \(methodText(own, meter: meter))")
                }
                if let billed = check.billedUse { row("\(prefix)Use billed", "\(NumberText.use(billed)) \(meter.unit)") }
                if let own = check.ownUse { row("\(prefix)Use shown by the meter", "\(NumberText.use(own)) \(meter.unit)") }
                y += 6
            }
            if let excess = result.excessUnits {
                let line: String
                switch result.status {
                case .overbilled: line = "Billed for \(NumberText.use(excess)) \(meter.unit) more than the meter shows."
                case .underbilled: line = "Billed for \(NumberText.use(-excess)) \(meter.unit) less than the meter shows."
                default: line = "The bill matches the meter within rounding."
                }
                text(line, font: heading, spacingAfter: 4)
                if let money = result.excessMoney.map(money.exact), let source = result.rateSource {
                    text("About \(money), \(source).", font: body, color: grey)
                }
            }
            text("Daily use between photos is (later reading − earlier reading) ÷ days between them. A reading for a date without a photo is worked out at that daily rate.", font: body, color: grey, spacingAfter: 16)

            if let billPhoto = photos.image(bill.photoFile) {
                newPage()
                text("Bill", font: heading)
                image(billPhoto, caption: "Photo of the bill.", maxHeight: 640)
            }

            let usedReadings = result.checks
                .flatMap { [$0.ownOpening, $0.ownClosing].compactMap { $0 } }
                .flatMap(\.readingsUsed)
            var seen = Set<UUID>()
            let unique = usedReadings.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }
            if !unique.isEmpty {
                newPage()
                text("Meter photos", font: heading)
                for reading in unique {
                    let caption = "\(DateText.full(reading.date)) at \(DateText.clock(reading.date)) — \(reading.register == .total ? "" : reading.register.title + " register ")\(meter.dialText(reading.value)) \(meter.unit). \(reading.source.title)."
                    if let photo = photos.image(reading.photoFile) {
                        image(photo, caption: caption)
                    } else {
                        text(caption + " No photo was attached to this reading.", font: body, spacingAfter: 12)
                    }
                }
            }
        }

        let safeName = meter.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meter Evidence \(safeName) \(DateText.full(bill.periodTo)).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func methodText(_ own: OwnValue, meter: MeterItem) -> String {
        switch own.method {
        case .photo(let reading):
            return "(photo taken \(DateText.full(reading.date)))"
        case .interpolated(let a, let b):
            return "(worked out from photos on \(DateText.full(a.date)) and \(DateText.full(b.date)))"
        case .extrapolated(let reading, let days):
            let direction = days >= 0 ? "after" : "before"
            return "(worked out \(DateText.days(abs(days))) \(direction) the photo of \(DateText.full(reading.date)), at the latest daily rate)"
        }
    }
}

enum Verdict {
    case bearing(String)
    case shuttered
}

enum Mutation {
    case readings([String: String])
    case strides([String: String])
    case swept
    case reseed([String: String])
    case route(String)
    case consent(Bool, Date)
    case stamp(Date)
}

