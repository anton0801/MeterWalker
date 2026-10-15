//
//  AppStore.swift
//  MeterWalk
//
//  The single source of truth. Every change goes through here, is saved to
//  disk shortly after, and reschedules reminders.
//

import SwiftUI
import UIKit

@MainActor
final class AppStore: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var state = AppState()
    /// A save or file problem to show in a banner.
    @Published var errorMessage: String?

    let persistence: Persistence
    let photos: PhotoStore
    let notifications: NotificationScheduler
    private var pendingSave: DispatchWorkItem?

    init(
        persistence: Persistence = Persistence(),
        photos: PhotoStore = PhotoStore(),
        notifications: NotificationScheduler = NotificationScheduler()
    ) {
        self.persistence = persistence
        self.photos = photos
        self.notifications = notifications
    }

    var money: MoneyText { MoneyText(currencyCode: state.settings.currencyCode) }

    // MARK: Loading and saving

    func load() async {
        loadState = .loading
        let persistence = self.persistence
        let result: Result<AppState, Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Result { try persistence.load() })
            }
        }
        switch result {
        case .success(let loaded):
            state = loaded
            loadState = .loaded
            notifications.reschedule(state: state)
        case .failure(let error):
            loadState = .failed(error.localizedDescription)
        }
    }

    /// After a load failure: moves the unreadable file aside and starts empty.
    func startFreshKeepingFile() -> String? {
        let name = try? persistence.setAsideUnreadableDocument()
        state = AppState()
        loadState = .loaded
        return name
    }

    private func mutate(_ change: (inout AppState) -> Void) {
        change(&state)
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeToDisk() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func writeToDisk() {
        pendingSave = nil
        persistence.save(state) { [weak self] error in
            if let error { self?.errorMessage = error.localizedDescription }
        }
        notifications.reschedule(state: state)
    }

    /// Writes immediately, used when the app goes to the background.
    func flush() {
        guard pendingSave != nil, loadState == .loaded else { return }
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try persistence.saveNow(state)
        } catch {
            errorMessage = error.localizedDescription
        }
        notifications.reschedule(state: state)
    }

    // MARK: Onboarding

    func addMeters(_ meters: [MeterItem]) {
        mutate { $0.meters.append(contentsOf: meters) }
    }

    func completeOnboarding() {
        mutate { $0.hasCompletedOnboarding = true }
    }

    // MARK: Meters

    func saveMeter(_ meter: MeterItem) {
        mutate { state in
            if let index = state.meters.firstIndex(where: { $0.id == meter.id }) {
                state.meters[index] = meter
            } else {
                state.meters.append(meter)
            }
        }
    }

    func deleteMeter(_ id: UUID) {
        guard let meter = state.meter(id) else { return }
        let readings = state.readings(for: id)
        readings.forEach { photos.delete($0.photoFile) }
        photos.delete(meter.photoFile)
        mutate { state in
            state.meters.removeAll { $0.id == id }
            state.readings.removeAll { $0.meterID == id }
            // Bills keep their own photo and amounts; they just lose the link.
            for index in state.bills.indices where state.bills[index].meterID == id {
                state.bills[index].meterID = nil
            }
        }
    }

    func setNightShare(_ share: Double?, for meterID: UUID) {
        mutate { state in
            guard let index = state.meters.firstIndex(where: { $0.id == meterID }) else { return }
            state.meters[index].nightShareAssumption = share
        }
    }

    // MARK: Photos

    func storePhoto(_ image: UIImage) throws -> String {
        try photos.save(image)
    }

    func discardPhoto(_ fileName: String?) {
        photos.delete(fileName)
    }

    // MARK: Readings

    /// Adds a checked reading. `settingAside` lists earlier readings to leave
    /// out of calculations (a typo, or replaced the same day), with why.
    func addReading(_ reading: Reading, settingAside: [UUID: String] = [:]) {
        mutate { state in
            for (id, note) in settingAside {
                if let index = state.readings.firstIndex(where: { $0.id == id }) {
                    state.readings[index].isSetAside = true
                    state.readings[index].setAsideNote = note
                }
            }
            state.readings.append(reading)
        }
        if let ratio = reading.confirmedUnusualRatio, let meter = state.meter(reading.meterID) {
            notifications.scheduleUnusualUse(meter: meter, ratio: ratio, enabled: state.settings.notifyUnusualUse)
        }
    }

    func updateReading(_ reading: Reading, settingAside: [UUID: String] = [:]) {
        mutate { state in
            for (id, note) in settingAside {
                if let index = state.readings.firstIndex(where: { $0.id == id }) {
                    state.readings[index].isSetAside = true
                    state.readings[index].setAsideNote = note
                }
            }
            if let index = state.readings.firstIndex(where: { $0.id == reading.id }) {
                state.readings[index] = reading
            }
        }
    }

    func restoreReading(_ id: UUID) {
        mutate { state in
            guard let index = state.readings.firstIndex(where: { $0.id == id }) else { return }
            state.readings[index].isSetAside = false
            state.readings[index].setAsideNote = nil
        }
    }

    func deleteReading(_ id: UUID) {
        guard let reading = state.readings.first(where: { $0.id == id }) else { return }
        photos.delete(reading.photoFile)
        mutate { $0.readings.removeAll { $0.id == id } }
    }

    // MARK: Tariffs

    func saveTariff(_ tariff: TariffItem) {
        mutate { state in
            if tariff.isCurrent {
                for index in state.tariffs.indices where state.tariffs[index].meterType == tariff.meterType {
                    state.tariffs[index].isCurrent = false
                }
            }
            if let index = state.tariffs.firstIndex(where: { $0.id == tariff.id }) {
                state.tariffs[index] = tariff
            } else {
                state.tariffs.append(tariff)
            }
        }
    }

    func makeCurrent(_ id: UUID) {
        guard var tariff = state.tariffs.first(where: { $0.id == id }) else { return }
        tariff.isCurrent = true
        saveTariff(tariff)
    }

    func deleteTariff(_ id: UUID) {
        mutate { $0.tariffs.removeAll { $0.id == id } }
    }

    // MARK: Bills

    func saveBill(_ bill: Bill) {
        mutate { state in
            if let index = state.bills.firstIndex(where: { $0.id == bill.id }) {
                state.bills[index] = bill
            } else {
                state.bills.append(bill)
            }
        }
    }

    func deleteBill(_ id: UUID) {
        guard let bill = state.bills.first(where: { $0.id == id }) else { return }
        photos.delete(bill.photoFile)
        mutate { $0.bills.removeAll { $0.id == id } }
    }

    // MARK: Appliances

    func saveAppliance(_ appliance: Appliance) {
        mutate { state in
            if let index = state.appliances.firstIndex(where: { $0.id == appliance.id }) {
                state.appliances[index] = appliance
            } else {
                state.appliances.append(appliance)
            }
        }
    }

    func deleteAppliance(_ id: UUID) {
        mutate { $0.appliances.removeAll { $0.id == id } }
    }

    // MARK: Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        mutate { change(&$0.settings) }
    }

    // MARK: Export, import, delete

    func exportBackup() throws -> URL {
        try BackupService.makeBackup(state: state, photos: photos)
    }

    func exportReadingsCSV() throws -> URL {
        try BackupService.makeReadingsCSV(state: state)
    }

    /// Replaces everything with the backup's contents.
    func importBackup(from url: URL) throws {
        let backup = try BackupService.readBackup(from: url)
        photos.deleteAll()
        for (name, data) in backup.photos {
            try photos.write(data: data, fileName: name)
        }
        var restored = backup.state
        restored.hasCompletedOnboarding = true
        pendingSave?.cancel()
        state = restored
        try persistence.saveNow(state)
        notifications.reschedule(state: state)
    }

    func deleteAllData() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try persistence.deleteDocument()
        } catch {
            errorMessage = error.localizedDescription
        }
        photos.deleteAll()
        notifications.removeAll()
        state = AppState()
    }
}
