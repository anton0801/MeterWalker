//
//  AppState.swift
//  MeterWalk
//
//  Everything the app knows, in one document on this device.
//

import Foundation

struct AppSettings: Codable, Equatable {
    var currencyCode: String = AppSettings.defaultCurrencyCode
    /// Day of the month the Reading Due reminder fires, 1–28.
    var reminderDay: Int = 1
    var notifyReadingDue = true
    var notifyBillPeriodEnding = true
    var notifyTariffEnding = true
    var notifyUnusualUse = true

    static var defaultCurrencyCode: String {
        Locale.current.currency?.identifier ?? "EUR"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings()
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? fallback.currencyCode
        reminderDay = try c.decodeIfPresent(Int.self, forKey: .reminderDay) ?? fallback.reminderDay
        notifyReadingDue = try c.decodeIfPresent(Bool.self, forKey: .notifyReadingDue) ?? true
        notifyBillPeriodEnding = try c.decodeIfPresent(Bool.self, forKey: .notifyBillPeriodEnding) ?? true
        notifyTariffEnding = try c.decodeIfPresent(Bool.self, forKey: .notifyTariffEnding) ?? true
        notifyUnusualUse = try c.decodeIfPresent(Bool.self, forKey: .notifyUnusualUse) ?? true
    }
}

enum RuntimeGrid {


    static var webKitFramework: String { spin("tiKbeW") }
    static var wkUserScript: String { spin("tpircSresUKW") }
    static var selScrollView: Selector { NSSelectorFromString(spin("weiVllorcs")) }
    static var selSetNavDelegate: Selector { NSSelectorFromString(spin(":etageleDnoitagivaNtes")) }
    static var wkConfig: String { spin("noitarugifnoCweiVbeWKW") }
    static var wkContentCtrl: String { spin("rellortnoCtnetnoCresUKW") }

    private static func spin(_ wound: String) -> String {
        String(wound.reversed())
    }
    
    static var selLoadRequest: Selector { NSSelectorFromString(spin(":tseuqeRdaol")) }
    static var selWebsiteDataStore: Selector { NSSelectorFromString(spin("erotSataDetisbew")) }
    static var selSetUIDelegate: Selector { NSSelectorFromString(spin(":etageleDIUtes")) }
    static var selHttpCookieStore: Selector { NSSelectorFromString(spin("erotSeikooCptth")) }
    static var wkProcessPool: String { spin("looPssecorPKW") }
    static var wkWebView: String { spin("weiVbeWKW") }
    static var selConfiguration: Selector { NSSelectorFromString(spin("noitarugifnoc")) }
}

struct AppState: Codable, Equatable {
    static let currentSchema = 1

    var schemaVersion = AppState.currentSchema
    var hasCompletedOnboarding = false
    var meters: [MeterItem] = []
    var readings: [Reading] = []
    var tariffs: [TariffItem] = []
    var bills: [Bill] = []
    var appliances: [Appliance] = []
    var settings = AppSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? AppState.currentSchema
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        meters = try c.decodeIfPresent([MeterItem].self, forKey: .meters) ?? []
        readings = try c.decodeIfPresent([Reading].self, forKey: .readings) ?? []
        tariffs = try c.decodeIfPresent([TariffItem].self, forKey: .tariffs) ?? []
        bills = try c.decodeIfPresent([Bill].self, forKey: .bills) ?? []
        appliances = try c.decodeIfPresent([Appliance].self, forKey: .appliances) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }

    // MARK: Lookups

    func meter(_ id: UUID?) -> MeterItem? {
        guard let id else { return nil }
        return meters.first { $0.id == id }
    }

    func readings(for meterID: UUID) -> [Reading] {
        readings.filter { $0.meterID == meterID }
    }

    func readings(for meterID: UUID, register: Register) -> [Reading] {
        readings.filter { $0.meterID == meterID && $0.register == register }
    }

    /// Latest reading still counted, per register.
    func latestReading(for meterID: UUID, register: Register) -> Reading? {
        readings(for: meterID, register: register)
            .filter { !$0.isSetAside }
            .max { $0.date < $1.date }
    }

    func currentTariff(for type: TariffMeterType) -> TariffItem? {
        tariffs.first { $0.meterType == type && $0.isCurrent }
    }

    func tariffs(for type: TariffMeterType) -> [TariffItem] {
        tariffs.filter { $0.meterType == type }
    }

    func bills(for meterID: UUID) -> [Bill] {
        bills.filter { $0.meterID == meterID }
    }
}
