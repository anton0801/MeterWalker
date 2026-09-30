//
//  Persistence.swift
//  MeterWalk
//
//  One JSON document in the app's Documents folder. No account, no network.
//

import Foundation

enum PersistenceError: LocalizedError {
    case readFailed(String)
    case decodeFailed(String)
    case writeFailed(String)
    case newerFormat(Int)

    var errorDescription: String? {
        switch self {
        case .readFailed(let detail): return "The data file could not be read. \(detail)"
        case .decodeFailed(let detail): return "The data file is damaged or incomplete. \(detail)"
        case .writeFailed(let detail): return "Your change could not be saved. \(detail)"
        case .newerFormat(let version):
            return "This data was written by a newer version of Meter Walk (format \(version)). Update the app to open it."
        }
    }
}

/// Holds only immutable configuration, so it is safe to use from a background queue.
final class Persistence: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let fileName: String
    private let queue = DispatchQueue(label: "app.meterwalk.persistence", qos: .utility)

    init(fileName: String = "meterwalk.json") {
        self.fileName = fileName
    }

    var directory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    var documentURL: URL { directory.appendingPathComponent(fileName) }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func load() throws -> AppState {
        guard fileManager.fileExists(atPath: documentURL.path) else {
            // First launch: an empty document. No sample meters or tariffs.
            return AppState()
        }
        let data: Data
        do {
            data = try Data(contentsOf: documentURL)
        } catch {
            throw PersistenceError.readFailed(error.localizedDescription)
        }
        if data.isEmpty { return AppState() }
        return try decode(data)
    }

    func decode(_ data: Data) throws -> AppState {
        let state: AppState
        do {
            state = try Persistence.decoder().decode(AppState.self, from: data)
        } catch {
            throw PersistenceError.decodeFailed(error.localizedDescription)
        }
        if state.schemaVersion > AppState.currentSchema {
            throw PersistenceError.newerFormat(state.schemaVersion)
        }
        return state
    }

    /// Writes off the main thread; the completion runs on the main queue.
    func save(_ state: AppState, completion: @escaping (Error?) -> Void) {
        let data: Data
        do {
            data = try Persistence.encoder().encode(state)
        } catch {
            completion(PersistenceError.writeFailed(error.localizedDescription))
            return
        }
        let url = documentURL
        queue.async {
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(PersistenceError.writeFailed(error.localizedDescription)) }
            }
        }
    }

    func saveNow(_ state: AppState) throws {
        do {
            let data = try Persistence.encoder().encode(state)
            try data.write(to: documentURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw PersistenceError.writeFailed(error.localizedDescription)
        }
    }

    /// Moves an unreadable file aside so the user can start again without it
    /// being destroyed. Returns the new file name.
    func setAsideUnreadableDocument() throws -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let name = "meterwalk-unreadable-\(stamp).json"
        try fileManager.moveItem(at: documentURL, to: directory.appendingPathComponent(name))
        return name
    }

    func deleteDocument() throws {
        if fileManager.fileExists(atPath: documentURL.path) {
            try fileManager.removeItem(at: documentURL)
        }
    }
}
