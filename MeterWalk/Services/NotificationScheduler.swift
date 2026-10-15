//
//  NotificationScheduler.swift
//  MeterWalk
//
//  Local reminders only: Reading Due, Bill Period Ending, Tariff Ending and
//  Unusual Use Detected. Rebuilt from the data every time it changes.
//

import Foundation
import UserNotifications

final class NotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    private let prefix = "meterwalk."

    enum Kind: String {
        case readingDue = "reading-due"
        case billPeriod = "bill-period"
        case tariffEnding = "tariff-ending"
        case unusualUse = "unusual-use"
    }

    func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Replaces every scheduled reminder except pending unusual-use follow-ups.
    func reschedule(state: AppState, now: Date = Date()) {
        center.getPendingNotificationRequests { [weak self] pending in
            guard let self else { return }
            let stale = pending.map(\.identifier).filter {
                $0.hasPrefix(self.prefix) && !$0.hasPrefix(self.prefix + Kind.unusualUse.rawValue)
            }
            self.center.removePendingNotificationRequests(withIdentifiers: stale)
            guard state.hasCompletedOnboarding else { return }
            for request in self.requests(state: state, now: now) {
                self.center.add(request)
            }
        }
    }

    func removeAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func requests(state: AppState, now: Date) -> [UNNotificationRequest] {
        var result: [UNNotificationRequest] = []
        let settings = state.settings
        let calendar = ConsumptionEngine.calendar

        if settings.notifyReadingDue, !state.meters.isEmpty {
            var components = DateComponents()
            components.day = min(28, max(1, settings.reminderDay))
            components.hour = 10
            let names = state.meters.count == 1 ? state.meters[0].name : "your \(state.meters.count) meters"
            result.append(request(
                kind: .readingDue, suffix: "monthly",
                title: "Reading due",
                body: "One photo of \(names) keeps your daily use and bill checks accurate.",
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            ))
        }

        if settings.notifyBillPeriodEnding {
            // The next period is assumed to be as long as the last one.
            for meter in state.meters {
                guard let last = state.bills(for: meter.id).max(by: { $0.periodTo < $1.periodTo }) else { continue }
                let length = max(7, ConsumptionEngine.daysBetween(last.periodFrom, last.periodTo))
                var next = ConsumptionEngine.addDays(length, to: last.periodTo)
                while next < now { next = ConsumptionEngine.addDays(length, to: next) }
                guard var fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: next), fire > now else { continue }
                if fire.timeIntervalSince(now) < 60 { fire = now.addingTimeInterval(60) }
                let supplier = last.supplier.isEmpty ? "Your" : "Your \(last.supplier)"
                result.append(request(
                    kind: .billPeriod, suffix: meter.id.uuidString,
                    title: "Bill period ending: \(meter.name)",
                    body: "\(supplier) bill period ends around today. A photo of the meter today makes the next bill easy to check.",
                    trigger: dateTrigger(fire)
                ))
            }
        }

        if settings.notifyTariffEnding {
            for tariff in state.tariffs {
                guard let end = tariff.endsOn else { continue }
                let warn = ConsumptionEngine.addDays(-14, to: end)
                guard let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: warn), fire > now else { continue }
                result.append(request(
                    kind: .tariffEnding, suffix: tariff.id.uuidString,
                    title: "Tariff ending: \(tariff.displayName)",
                    body: "It ends on \(DateText.full(end)). Run a Tariff Replay on your real use before you renew.",
                    trigger: dateTrigger(fire)
                ))
            }
        }
        return result
    }

    /// A follow-up three days after a reading far above usual was confirmed.
    func scheduleUnusualUse(meter: MeterItem, ratio: Double, enabled: Bool) {
        guard enabled else { return }
        let fire = Date().addingTimeInterval(3 * 24 * 3600)
        let body = "Your last \(meter.name) reading was \(NumberText.one(ratio)) times your usual daily use. Another reading shows whether it is still running high."
        center.add(request(kind: .unusualUse, suffix: meter.id.uuidString, title: "Unusual use detected", body: body, trigger: dateTrigger(fire)))
    }

    private func request(kind: Kind, suffix: String, title: String, body: String, trigger: UNNotificationTrigger) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = kind.rawValue
        return UNNotificationRequest(identifier: "\(prefix)\(kind.rawValue).\(suffix)", content: content, trigger: trigger)
    }

    private func dateTrigger(_ date: Date) -> UNCalendarNotificationTrigger {
        let components = ConsumptionEngine.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}
