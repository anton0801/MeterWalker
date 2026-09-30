//
//  SettingsView.swift
//  MeterWalk
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var sharing: SharedFile?
    @State private var importing = false
    @State private var pendingImport: URL?
    @State private var confirmingDelete = false
    @State private var confirmingDeleteAgain = false
    @State private var notificationsDenied = false
    @State private var message: String?

    private let currencies = ["EUR", "GBP", "USD", "CHF", "PLN", "CZK", "SEK", "NOK", "DKK", "HUF", "RON", "BGN", "TRY", "UAH", "KZT", "GEL", "RUB", "CAD", "AUD", "NZD", "JPY", "INR", "ZAR", "BRL", "MXN"]

    var body: some View {
        ScreenScroll(spacing: 24) {
            ScreenTitle("settings")

            TitledSection(title: "Your data") {
                Panel(padding: 14) {
                    VStack(spacing: 0) {
                        NavigationLink(value: Route.meters) {
                            NavigationRowLabel(symbol: "speedometer", title: "Meters", detail: "\(store.state.meters.count)", tint: Palette.yellow)
                        }
                        Divider2()
                        NavigationLink(value: Route.tariffs) {
                            NavigationRowLabel(symbol: "tag.fill", title: "Tariffs", detail: "\(store.state.tariffs.count)", tint: Palette.yellow)
                        }
                        Divider2()
                        NavigationLink(value: Route.appliances) {
                            NavigationRowLabel(symbol: "powerplug.fill", title: "Appliance Estimates", detail: "\(store.state.appliances.count)", tint: Palette.yellow)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            TitledSection(title: "Currency") {
                Panel(padding: 14) {
                    HStack {
                        Text("Currency")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.white)
                        Spacer()
                        Picker("Currency", selection: Binding(
                            get: { store.state.settings.currencyCode },
                            set: { code in store.updateSettings { $0.currencyCode = code } }
                        )) {
                            ForEach(currencyOptions, id: \.self) { code in
                                Text("\(code) \(MoneyText(currencyCode: code).symbol)").tag(code)
                            }
                        }
                        .tint(Palette.yellow)
                    }
                }
            }

            TitledSection(title: "Reminders") {
                Panel(padding: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        StepperRow(
                            title: "Reading Reminder Day",
                            value: Binding(
                                get: { store.state.settings.reminderDay },
                                set: { day in store.updateSettings { $0.reminderDay = day } }
                            ),
                            range: 1...28,
                            display: { "\($0)" }
                        )
                        Text("Day of the month for the Reading Due reminder, at 10:00.")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.tertiaryText)
                        Divider2()
                        toggle("Reading Due", detail: "Once a month on the day above.", \.notifyReadingDue)
                        toggle("Bill Period Ending", detail: "When a bill period is about to end, so you have a photo for that date.", \.notifyBillPeriodEnding)
                        toggle("Tariff Ending", detail: "Two weeks before a tariff's end date.", \.notifyTariffEnding)
                        toggle("Unusual Use Detected", detail: "A follow-up after a reading far above your usual use.", \.notifyUnusualUse)
                        if notificationsDenied {
                            AssumptionNote(text: "Notifications are off for Meter Walk in iOS Settings, so reminders cannot appear.", symbol: "bell.slash", color: Palette.red)
                        }
                    }
                }
            }

            TitledSection(title: "Backup") {
                Panel(padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Export Data") { export(backup: true) }
                            .buttonStyle(.secondary)
                        Text("One file with every meter, reading, tariff, bill and photo. Save it to Files or send it to yourself.")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Export Readings as CSV") { export(backup: false) }
                            .buttonStyle(InlineButtonStyle())
                        Divider2()
                        Button("Import Backup") { importing = true }
                            .buttonStyle(.secondary)
                        Text("Replaces everything in the app with the backup's contents.")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }
            }

            if let message {
                AssumptionNote(text: message, symbol: "checkmark.circle", color: Palette.white)
            }

            TitledSection(title: "About") {
                Panel(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        KeyValueRow(key: "Version", value: appVersion, mono: true)
                        Text("Meter Walk keeps everything on this iPhone. Numbers are read from photos on the device. There is no account and nothing is sent anywhere.")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Costs are worked out from your readings and the tariffs you enter. They are not bills, and the app does not give financial advice.")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Button("Delete All App Data") { confirmingDelete = true }
                .buttonStyle(.destructive)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: checkNotifications)
        .sheet(item: $sharing) { file in
            ShareSheet(items: [file.url]).ignoresSafeArea()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { pendingImport = url }
        }
        .alert("Replace everything with this backup?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Replace", role: .destructive) {
                guard let url = pendingImport else { return }
                pendingImport = nil
                do {
                    try store.importBackup(from: url)
                    message = "Backup imported."
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("The meters, readings, photos, tariffs and bills on this iPhone are replaced by the ones in the backup.")
        }
        .alert("Delete all app data?", isPresented: $confirmingDelete) {
            Button("Continue", role: .destructive) { confirmingDeleteAgain = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every meter, reading, photo, tariff and bill is removed from this iPhone. Export a backup first if you may need them as proof.")
        }
        .alert("This cannot be undone", isPresented: $confirmingDeleteAgain) {
            Button("Delete Everything", role: .destructive) { store.deleteAllData() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var currencyOptions: [String] {
        let current = store.state.settings.currencyCode
        return currencies.contains(current) ? currencies : [current] + currencies
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func toggle(_ title: String, detail: String, _ keyPath: WritableKeyPath<AppSettings, Bool>) -> some View {
        ToggleRow(
            title: title,
            detail: detail,
            isOn: Binding(
                get: { store.state.settings[keyPath: keyPath] },
                set: { value in
                    store.updateSettings { $0[keyPath: keyPath] = value }
                    if value { requestNotifications() }
                }
            )
        )
    }

    private func checkNotifications() {
        store.notifications.authorizationStatus { status in
            notificationsDenied = status == .denied
        }
    }

    private func requestNotifications() {
        store.notifications.authorizationStatus { status in
            if status == .notDetermined {
                store.notifications.requestPermission { _ in checkNotifications() }
            } else {
                notificationsDenied = status == .denied
            }
        }
    }

    private func export(backup: Bool) {
        do {
            let url = backup ? try store.exportBackup() : try store.exportReadingsCSV()
            sharing = SharedFile(url: url)
        } catch {
            store.errorMessage = "The export could not be made: \(error.localizedDescription)"
        }
    }
}
