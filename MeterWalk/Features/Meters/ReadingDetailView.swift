//
//  ReadingDetailView.swift
//  MeterWalk
//
//  One reading and its photo. Readings can be corrected, set aside, or
//  deleted with their photo.
//

import SwiftUI

struct ReadingDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let readingID: UUID

    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if let reading = store.state.readings.first(where: { $0.id == readingID }),
               let meter = store.state.meter(reading.meterID) {
                content(reading, meter: meter)
            } else {
                ScreenScroll {
                    EmptyStatePanel(symbol: "trash", title: "Reading deleted", message: "This reading is no longer in the app.")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ reading: Reading, meter: Meter) -> some View {
        let interval = ConsumptionEngine.intervals(meter: meter, register: reading.register, readings: store.state.readings)
            .first { $0.endReadingID == reading.id }
        return ScreenScroll(spacing: 20) {
            ScreenTitle("reading", subtitle: "\(meter.name)\(reading.register == .total ? "" : " · \(reading.register.title) \(reading.register.meterLabel)")")

            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    RecessedDisplay {
                        FittedLCD(
                            text: meter.dialText(reading.value),
                            color: reading.isSetAside ? Palette.tertiaryText : Palette.utility(meter.utility),
                            unit: meter.unit
                        )
                    }
                    KeyValueRow(key: "Taken", value: "\(DateText.full(reading.date)), \(DateText.clock(reading.date))")
                    KeyValueRow(key: "Source", value: reading.source.title)
                    if let reason = reading.dropReason {
                        KeyValueRow(key: "Lower than before", value: reason.title, valueColor: Palette.blue)
                    }
                    if let ratio = reading.confirmedUnusualRatio {
                        KeyValueRow(key: "Unusual jump", value: "×\(NumberText.one(ratio)), confirmed real", valueColor: Palette.red)
                    }
                    if let interval {
                        KeyValueRow(key: "Since previous", value: "\(NumberText.use(interval.use)) \(meter.unit) in \(DateText.days(interval.days))")
                        KeyValueRow(key: "Per day", value: "\(NumberText.rate(interval.dailyRate)) \(meter.unit)\(interval.isRough ? ", rough" : "")", mono: true)
                    }
                    if !reading.note.isEmpty {
                        Divider2()
                        Text(reading.note)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }

            if reading.isSetAside {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        AssumptionNote(text: reading.setAsideNote ?? "Set aside: left out of every calculation.", symbol: "minus.circle")
                        Button("Count This Reading Again") { store.restoreReading(reading.id) }
                            .buttonStyle(.secondary)
                    }
                }
            }

            if reading.photoFile != nil {
                TitledSection(title: "Photo") {
                    PhotoPanel(fileName: reading.photoFile, caption: "Kept as proof of this reading.", height: 260)
                }
            } else {
                AssumptionNote(text: "Typed without a photo, so there is no proof of this reading if a bill is disputed.", symbol: "camera")
            }

            VStack(spacing: 12) {
                Button("Correct This Reading") { editing = true }
                    .buttonStyle(.secondary)
                if !reading.isSetAside {
                    Button("Leave Out of Calculations") {
                        store.updateReading(reading, settingAside: [reading.id: "Set aside by you."])
                    }
                    .buttonStyle(.secondary)
                }
                Button("Delete Reading") { confirmingDelete = true }
                    .buttonStyle(.destructive)
            }
        }
        .sheet(isPresented: $editing) {
            ReadingEditorView(meter: meter, reading: reading)
        }
        .alert("Delete this reading?", isPresented: $confirmingDelete) {
            Button("Delete Reading and Photo", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    store.deleteReading(reading.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its photo is deleted too. If it might be needed as proof for a bill, set it aside instead.")
        }
    }
}

/// Corrects the number, date or note of a saved reading, with the same
/// checks as a new one.
struct ReadingEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let meter: Meter
    let reading: Reading

    @State private var text: String
    @State private var date: Date
    @State private var note: String
    @State private var dropReason: DropReason?
    @State private var confirmUnusual = false

    init(meter: Meter, reading: Reading) {
        self.meter = meter
        self.reading = reading
        _text = State(initialValue: NumberText.editable(reading.value))
        _date = State(initialValue: reading.date)
        _note = State(initialValue: reading.note)
        _dropReason = State(initialValue: reading.dropReason)
        _confirmUnusual = State(initialValue: reading.confirmedUnusualRatio != nil)
    }

    private var value: Double? { NumberText.parse(text) }

    private var issue: ReadingIssue? {
        guard let value else { return nil }
        let draft = ReadingDraft(
            meterID: meter.id, register: reading.register, date: date, value: value,
            dropReason: dropReason, acknowledgedUnusual: confirmUnusual, acknowledgedSameDay: false
        )
        return ReadingValidator.firstIssue(for: draft, meter: meter, readings: store.state.readings, replacing: reading.id)
    }

    private var isLower: Bool {
        guard let value,
              let previous = ReadingValidator.previousReading(meterID: meter.id, register: reading.register, before: date, readings: store.state.readings.filter { $0.id != reading.id })
        else { return false }
        return value < previous.value
    }

    var body: some View {
        EditorSheet(title: "Correct Reading", canSave: value != nil && issue == nil, onCancel: { dismiss() }, onSave: save) {
            RecessedDisplay {
                FittedLCD(text: meter.dialText(value ?? 0), color: Palette.utility(meter.utility), rollFromZero: false, unit: meter.unit)
            }
            NumberFieldBox(title: "Reading", text: $text, unit: meter.unit, invalid: value == nil || issue != nil)
            Panel(padding: 14) {
                DateRow(title: "Taken", date: $date, components: [.date, .hourAndMinute], range: Date.distantPast...Date())
            }
            if isLower {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Why is it lower than the one before?")
                    SegmentPicker(options: [DropReason?.none, .meterReplaced, .rolledOver], selection: $dropReason) {
                        $0?.title ?? "Choose"
                    }
                    Text("A typo in the earlier reading is fixed on that reading instead.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
            if let issue {
                issueNote(issue)
            }
            TextFieldBox(title: "Note", text: $note, placeholder: "Optional", capitalization: .sentences)
        }
    }

    @ViewBuilder
    private func issueNote(_ issue: ReadingIssue) -> some View {
        switch issue {
        case .unusual(let ratio, _, _):
            Panel(padding: 14) {
                ToggleRow(title: "This is \(NumberText.one(ratio)) times your usual daily use. It is real.", isOn: $confirmUnusual)
            }
        case .lowerThanPrevious:
            AssumptionNote(text: "Lower than the reading before it. Choose a reason above, or fix the number.", symbol: "exclamationmark.triangle.fill", color: Palette.red)
        case .higherThanLater(let later):
            AssumptionNote(text: "Higher than the later reading of \(meter.dialText(later.value)) on \(DateText.short(later.date)).", symbol: "exclamationmark.triangle.fill", color: Palette.red)
        case .sameDay(let existing):
            AssumptionNote(text: "Another reading, \(meter.dialText(existing.value)), is already counted on this day. Pick another date, or set that one aside first.", symbol: "exclamationmark.triangle.fill", color: Palette.red)
        case .exceedsDial(let maximum):
            AssumptionNote(text: "The dial only goes up to \(meter.dialText(maximum)).", symbol: "exclamationmark.triangle.fill", color: Palette.red)
        case .rolloverImplausible:
            AssumptionNote(text: "These numbers do not fit a roll-over of the dial.", symbol: "exclamationmark.triangle.fill", color: Palette.red)
        }
    }

    private func save() {
        guard let value, issue == nil else { return }
        var updated = reading
        updated.value = value
        updated.date = date
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.dropReason = isLower ? dropReason : nil
        if !confirmUnusual { updated.confirmedUnusualRatio = nil }
        if case .unusual(let ratio, _, _)? = ReadingValidator.firstIssue(
            for: ReadingDraft(meterID: meter.id, register: reading.register, date: date, value: value, dropReason: updated.dropReason),
            meter: meter, readings: store.state.readings, replacing: reading.id
        ), confirmUnusual {
            updated.confirmedUnusualRatio = ratio
        }
        if updated.source == .recognized && value != reading.value {
            updated.source = .typedWithPhoto
        }
        store.updateReading(updated)
        dismiss()
    }
}
