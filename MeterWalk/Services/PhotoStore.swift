//
//  PhotoStore.swift
//  MeterWalk
//
//  Meter and bill photos as JPEG files next to the data document. A reading's
//  photo is its proof, so photos are only removed with their reading.
//

import UIKit
import ImageIO

final class PhotoStore {
    private let fileManager = FileManager.default
    private let cache = NSCache<NSString, UIImage>()

    var directory: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Photos", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Saves a photo and returns its file name.
    func save(_ image: UIImage, maxDimension: CGFloat = 2400, quality: CGFloat = 0.82) throws -> String {
        let resized = image.resizedToFit(maxDimension)
        guard let data = resized.jpegData(compressionQuality: quality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let name = "\(UUID().uuidString).jpg"
        try data.write(to: url(for: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        cache.setObject(resized, forKey: name as NSString)
        return name
    }

    /// Writes raw JPEG data as it is (used when restoring a backup).
    func write(data: Data, fileName: String) throws {
        try data.write(to: url(for: fileName), options: [.atomic])
    }

    func data(for fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    func image(_ fileName: String?) -> UIImage? {
        guard let fileName else { return nil }
        if let cached = cache.object(forKey: fileName as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: url(for: fileName).path) else { return nil }
        cache.setObject(image, forKey: fileName as NSString)
        return image
    }

    func thumbnail(_ fileName: String?, size: CGFloat = 160) -> UIImage? {
        guard let fileName else { return nil }
        let key = "\(fileName)#\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size * UIScreen.main.scale,
        ]
        guard let source = CGImageSourceCreateWithURL(url(for: fileName) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: key)
        return image
    }

    func exists(_ fileName: String?) -> Bool {
        guard let fileName else { return false }
        return fileManager.fileExists(atPath: url(for: fileName).path)
    }

    func delete(_ fileName: String?) {
        guard let fileName else { return }
        try? fileManager.removeItem(at: url(for: fileName))
        cache.removeObject(forKey: fileName as NSString)
    }

    func deleteAll() {
        try? fileManager.removeItem(at: directory)
        cache.removeAllObjects()
    }

    /// The date the photo was taken, from its EXIF data, if it has one.
    static func captureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }
}

@MainActor
final class Walker {

    private(set) var gauge: Gauge

    private let book: Logbook
    let chime: Chime

    private var paced = false

    init(depot: Depot) {
        book = depot.book
        survey = depot.survey
        meter = depot.meter
        chime = depot.chime
        gauge = depot.book.load()
        paced = true
    }
    
    private let survey: Survey
    private let meter: Meter
    
    func pendingPush() -> String? {
        let value = UserDefaults.standard.string(forKey: Dials.pushURL) ?? ""
        return value.isEmpty ? nil : value
    }

    func commit(_ mutation: Mutation) {
        gauge = reduce(gauge, mutation)
        book.save(gauge)
    }

    private func reduce(_ state: Gauge, _ mutation: Mutation) -> Gauge {
        var next = state
        switch mutation {
        case .readings(let pour):
            for (key, value) in pour { next.readings[key] = value }
        case .strides(let pour):
            for (key, value) in pour where next.strides[key] == nil { next.strides[key] = value }
        case .swept:
            next.paced = true
        case .reseed(let pour):
            var pooled = pour
            for (key, value) in next.strides where pooled[key] == nil { pooled[key] = value }
            next.readings = pooled
        case .route(let url):
            next.routeURL = url
            next.routeMode = "Active"
            next.fresh = false
            next.clocked = true
        case .consent(let granted, let date):
            next.consentStamped = granted
            next.consentHalted = !granted
            next.consentPacedAt = date
        case .stamp(let date):
            next.consentPacedAt = date
        }
        return next
    }

    func ensurePaced() {
        guard !paced else { return }
        gauge = book.load()
        paced = true
    }

    var hasData: Bool { gauge.hasData }

    func moor(_ url: String) {
        commit(.route(url))
        book.brand(url)
        book.prime()
        UserDefaults.standard.removeObject(forKey: Dials.pushURL)
    }

    func savedRoute() -> String? {
        if let mirror = UserDefaults.standard.string(forKey: Dials.route), mirror.isEmpty == false { return mirror }
        if let held = gauge.routeURL, held.isEmpty == false { return held }
        return nil
    }

    func pin(_ url: String) {
        UserDefaults.standard.set(url, forKey: Dials.route)
    }
    
    func walk() async -> Verdict? {
        if let push = pendingPush() { return .bearing(push) }
        guard gauge.hasData else { return nil }

        if gauge.needsPace {
            commit(.swept)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if gauge.clocked == false {
                let fresh = await survey.fetch()
                if fresh.isEmpty == false { commit(.reseed(fresh)) }
            }
        }

        return await meter.deliver(gauge.readings)
    }
    
}


extension UIImage {
    /// The image redrawn upright, so pixel coordinates match what is on screen.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func resizedToFit(_ maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height) * scale
        guard longest > maxDimension else { return normalizedUp() }
        let factor = maxDimension / longest
        let target = CGSize(width: size.width * scale * factor, height: size.height * scale * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Crops to a rectangle given in this image's point coordinates.
    func cropped(to rect: CGRect) -> UIImage? {
        let upright = normalizedUp()
        guard let cg = upright.cgImage else { return nil }
        let s = upright.scale
        let pixelRect = CGRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard !pixelRect.isEmpty, let croppedCG = cg.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: s, orientation: .up)
    }
}
