//
//  BackupService.swift
//  MeterWalk
//
//  Export: one backup file with every reading and every photo, and a CSV of
//  readings for spreadsheets. Import replaces everything from a backup file.
//

import Foundation

struct BackupFile: Codable {
    static let format = "meterwalk-backup"
    var format = BackupFile.format
    var version = 1
    var exportedAt = Date()
    var state: AppState
    /// Photo file name → JPEG bytes.
    var photos: [String: Data]
}

enum BackupError: LocalizedError {
    case notABackup
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notABackup: return "This file is not a Meter Walk backup."
        case .unreadable(let detail): return "The backup could not be read. \(detail)"
        }
    }
}

enum BackupService {
    static func referencedPhotos(in state: AppState) -> Set<String> {
        var names = Set<String>()
        state.meters.compactMap(\.photoFile).forEach { names.insert($0) }
        state.readings.compactMap(\.photoFile).forEach { names.insert($0) }
        state.bills.compactMap(\.photoFile).forEach { names.insert($0) }
        return names
    }

    static func makeBackup(state: AppState, photos: PhotoStore) throws -> URL {
        var files: [String: Data] = [:]
        for name in referencedPhotos(in: state) {
            if let data = photos.data(for: name) { files[name] = data }
        }
        let backup = BackupFile(state: state, photos: files)
        let data = try Persistence.encoder().encode(backup)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meter Walk Backup \(fileStamp()).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func readBackup(from url: URL) throws -> BackupFile {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.unreadable(error.localizedDescription)
        }
        let backup: BackupFile
        do {
            backup = try Persistence.decoder().decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.notABackup
        }
        guard backup.format == BackupFile.format else { throw BackupError.notABackup }
        if backup.state.schemaVersion > AppState.currentSchema {
            throw PersistenceError.newerFormat(backup.state.schemaVersion)
        }
        return backup
    }

    static func makeReadingsCSV(state: AppState) throws -> URL {
        var lines = ["Meter,Type,Register,Date,Time,Reading,Unit,Source,Photo,Set Aside,Reason,Note"]
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH:mm"
        let sorted = state.readings.sorted { $0.date < $1.date }
        for reading in sorted {
            guard let meter = state.meter(reading.meterID) else { continue }
            let fields = [
                meter.name,
                meter.kind.title,
                reading.register.title,
                iso.string(from: reading.date),
                time.string(from: reading.date),
                String(format: "%.\(meter.digitsAfterDecimal)f", reading.value),
                meter.unit,
                reading.source.title,
                reading.photoFile == nil ? "No" : "Yes",
                reading.isSetAside ? "Yes" : "No",
                reading.dropReason?.title ?? "",
                reading.note,
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meter Walk Readings \(fileStamp()).csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func fileStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
