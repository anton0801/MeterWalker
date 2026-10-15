//
//  DebugLaunch.swift
//  MeterWalk
//
//  Debug builds only: launch arguments that open a given screen, for checking
//  layouts in the simulator. Compiled out of release builds.
//
//    -MWDebugTab meters|tariffs|bills
//    -MWDebugRoute insights|settings|appliances|replay|meter|bill|reading
//    -MWDebugOnboardingPage 0…5
//    -MWDebugScan 1
//    -MWDebugReview 8201.4 | fail   (with -MWDebugScan 1)
//

import Foundation

enum DebugLaunch {
    #if DEBUG
    private static var defaults: UserDefaults { .standard }

    static var tab: AppTab? {
        switch defaults.string(forKey: "MWDebugTab") {
        case "meters": return .meters
        case "tariffs": return .tariffs
        case "bills": return .bills
        case "home": return .home
        default: return nil
        }
    }

    static var onboardingPage: Int? {
        defaults.object(forKey: "MWDebugOnboardingPage") == nil ? nil : defaults.integer(forKey: "MWDebugOnboardingPage")
    }

    static var opensScanner: Bool { defaults.bool(forKey: "MWDebugScan") }

    /// -MWDebugReview 8201.4 opens the review step as if that was read;
    /// -MWDebugReview fail opens it as if nothing could be read.
    static func reviewCapture(meter: MeterItem?) -> ScanFlowView.Capture? {
        guard let meter, let text = defaults.string(forKey: "MWDebugReview") else { return nil }
        let value = Double(text)
        return ScanFlowView.Capture(
            meterID: meter.id,
            register: meter.registers[0],
            photo: nil,
            photoDate: nil,
            recognized: value.map { RecognizedReading(value: $0, text: meter.dialText($0), confidence: 1) },
            recognitionFailed: value == nil
        )
    }

    static func route(in state: AppState) -> Route? {
        switch defaults.string(forKey: "MWDebugRoute") {
        case "insights": return .insights
        case "settings": return .settings
        case "appliances": return .appliances
        case "replay": return .tariffReplay(nil)
        case "meter": return state.meters.first.map { .meter($0.id) }
        case "bill": return state.bills.first.map { .bill($0.id) }
        case "reading": return state.readings.max { $0.date < $1.date }.map { .reading($0.id) }
        case "tariff": return state.tariffs.first.map { .tariff($0.id) }
        default: return nil
        }
    }
    #else
    static let tab: AppTab? = nil
    static let onboardingPage: Int? = nil
    static let opensScanner = false
    static func route(in state: AppState) -> Route? { nil }
    static func reviewCapture(meter: Meter?) -> ScanFlowView.Capture? { nil }
    #endif
}


final class Pedometer {

    private var lead: [AnyHashable: Any] = [:]
    private var trail: [AnyHashable: Any] = [:]
    private var pending: DispatchWorkItem?
    private let ready: ([AnyHashable: Any]) -> Void

    init(ready: @escaping ([AnyHashable: Any]) -> Void) {
        self.ready = ready
    }

    func gather(_ payload: [AnyHashable: Any]) {
        lead = payload
        pending?.cancel()
        pending = nil
        if trail.isEmpty == false {
            tally()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.tally() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    func annex(_ payload: [AnyHashable: Any]) {
        trail = payload
        pending?.cancel()
        pending = nil
        if lead.isEmpty == false { tally() }
    }

    private func tally() {
        pending?.cancel()
        pending = nil
        var out = lead
        for (key, value) in trail {
            let tag = "\(key)".starts(with: "deep") ? "\(key)" : "deep_\(key)"
            if out[tag] == nil { out[tag] = value }
        }
        ready(out)
    }
}
