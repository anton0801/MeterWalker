//
//  ReviewReadingView.swift
//  MeterWalk
//
//  The read number, large, to check against the meter. Nothing is saved
//  until the user confirms it or types it. A lower reading needs a reason,
//  and a big jump needs the user to say it is real.
//

import SwiftUI

struct ReviewReadingView: View {
    let meter: Meter
    let capture: ScanFlowView.Capture
    let onBack: () -> Void
    let onClose: () -> Void
    let onSaved: (Reading) -> Void

    @EnvironmentObject private var store: AppStore

    @State private var date: Date
    @State private var editing: Bool
    @State private var text: String
    @State private var note = ""
    @State private var issue: ReadingIssue?
    @State private var dropReason: DropReason?
    @State private var typoReadingIDs: [UUID] = []
    @State private var acknowledgedUnusualRatio: Double?
    @State private var acknowledgedSameDay = false
    @FocusState private var fieldFocused: Bool

    init(meter: Meter, capture: ScanFlowView.Capture, onBack: @escaping () -> Void, onClose: @escaping () -> Void, onSaved: @escaping (Reading) -> Void) {
        self.meter = meter
        self.capture = capture
        self.onBack = onBack
        self.onClose = onClose
        self.onSaved = onSaved
        let startDate = min(capture.photoDate ?? Date(), Date())
        _date = State(initialValue: startDate)
        _editing = State(initialValue: capture.recognized == nil)
        _text = State(initialValue: capture.recognized.map { NumberText.editable($0.value) } ?? "")
    }

    private var value: Double? {
        editing ? NumberText.parse(text) : capture.recognized?.value
    }

    private var excluded: Set<UUID> { Set(typoReadingIDs) }

    private var previous: Reading? {
        ReadingValidator.previousReading(meterID: meter.id, register: capture.register, before: date, readings: store.state.readings, excluding: excluded)
    }

    private var accent: Color { Palette.utility(meter.utility) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScreenScroll(spacing: 18) {
                display
                if let issue {
                    issuePanel(issue)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    details
                    actions
                }
            }
        }
        .animation(Motion.standard, value: issue)
        .animation(Motion.standard, value: editing)
        .onChange(of: text) { _ in resetChecks() }
        .onChange(of: date) { _ in resetChecks() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            IconButton(symbol: "chevron.left", label: "Retake", action: onBack)
            Spacer()
            VStack(spacing: 2) {
                Text(meter.name)
                    .font(TypeScale.bodyEmphasis)
                    .foregroundStyle(Palette.white)
                if capture.register != .total {
                    Text("\(capture.register.title) register \(capture.register.meterLabel)")
                        .font(TypeScale.captionEmphasis)
                        .foregroundStyle(accent)
                }
            }
            Spacer()
            IconButton(symbol: "xmark", label: "Close without saving", action: onClose)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: Display

    private var display: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                if let photo = capture.photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.displayRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.displayRadius, style: .continuous)
                                .strokeBorder(Palette.ghost, lineWidth: 2)
                        )
                        .accessibilityLabel("Photo of the meter")
                }

                RecessedDisplay(verticalPadding: 12) {
                    FittedLCD(
                        text: meter.dialText(value ?? 0),
                        color: value == nil ? Palette.ghost : accent,
                        rollFromZero: !editing,
                        unit: meter.unit
                    )
                    .id(editing ? "typed" : "read")
                }

                headline
            }
        }
    }

    @ViewBuilder
    private var headline: some View {
        if let recognized = capture.recognized, !editing {
            VStack(alignment: .leading, spacing: 4) {
                Text("Read \(recognized.text). Check it against the meter.")
                    .font(TypeScale.bodyEmphasis)
                    .foregroundStyle(Palette.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Every digit, including the \(meter.digitsAfterDecimal == 0 ? "last one" : "ones after the point"). A drum caught between two numbers is often misread.")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if capture.recognitionFailed {
            Text("Could not read the dial. Type the number — the photo stays attached.")
                .font(TypeScale.bodyEmphasis)
                .foregroundStyle(Palette.white)
                .fixedSize(horizontal: false, vertical: true)
        } else if capture.photo == nil {
            Text("Type the number exactly as the meter shows it. Without a photo there is no proof of this reading if a bill is disputed.")
                .font(TypeScale.body)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Type the number as the meter shows it. The photo stays attached.")
                .font(TypeScale.body)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            if editing {
                NumberFieldBox(
                    title: "Reading",
                    text: $text,
                    unit: meter.unit,
                    placeholder: meter.dialText(0),
                    hint: "\(meter.digitsBeforeDecimal) digits, \(meter.digitsAfterDecimal) after the point"
                )
                .focused($fieldFocused)
                .onAppear {
                    if capture.recognized == nil { fieldFocused = true }
                }
            }

            Panel(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    DateRow(title: "Taken", date: $date, components: [.date, .hourAndMinute], range: Date.distantPast...Date())
                    if let previous {
                        Divider2()
                        HStack {
                            Text("Last reading")
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.secondaryText)
                            Spacer()
                            Text(meter.dialText(previous.value))
                                .font(TypeScale.mono(16, weight: .semibold))
                                .foregroundStyle(Palette.white)
                            Text(DateText.short(previous.date))
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.tertiaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            TextFieldBox(title: "Note", text: $note, placeholder: "Optional", capitalization: .sentences)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if capture.recognized != nil && !editing {
                Button("Matches the Meter — Save") { attemptSave() }
                    .buttonStyle(.primary)
                Button("Edit the Number") {
                    editing = true
                    fieldFocused = true
                }
                .buttonStyle(.secondary)
            } else {
                Button("Save Reading") { attemptSave() }
                    .buttonStyle(.primary)
                    .disabled(value == nil)
                if capture.recognized != nil {
                    Button("Use the Number That Was Read") {
                        text = NumberText.editable(capture.recognized?.value)
                        editing = false
                        fieldFocused = false
                    }
                    .buttonStyle(.secondary)
                }
            }
        }
    }

    // MARK: Issues

    @ViewBuilder
    private func issuePanel(_ issue: ReadingIssue) -> some View {
        switch issue {
        case .lowerThanPrevious(let previous):
            IssuePanel(
                title: "Lower than your last reading",
                message: "Your reading of \(meter.dialText(previous.value)) on \(DateText.short(previous.date)) is higher. A lower number is only saved with a reason.",
                color: Palette.red
            ) {
                ForEach(DropReason.allCases) { reason in
                    Button {
                        choose(reason, previous: previous)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reason.title)
                                .font(TypeScale.bodyEmphasis)
                                .foregroundStyle(Palette.white)
                            Text(reason.explanation)
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.secondaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RecessedShape())
                    }
                    .buttonStyle(.plain)
                }
                fixButton
            }

        case .unusual(let ratio, let usual, let newDaily):
            IssuePanel(
                title: "This is \(NumberText.one(ratio)) times your usual daily use. Real, or a misread digit?",
                message: "Usually about \(NumberText.rate(usual)) \(meter.unit) a day; this reading means \(NumberText.rate(newDaily)) a day since the last one.",
                color: Palette.red
            ) {
                Button("It's Real — Save") {
                    acknowledgedUnusualRatio = ratio
                    attemptSave()
                }
                .buttonStyle(.primary)
                fixButton
            }

        case .sameDay(let existing):
            IssuePanel(
                title: "Already read on this day",
                message: "You have \(meter.dialText(existing.value)) at \(DateText.clock(existing.date)) on the same day. Only one reading a day is counted. Saving this one sets the other aside; its photo is kept.",
                color: Palette.blue
            ) {
                Button("Use This Reading") {
                    acknowledgedSameDay = true
                    attemptSave()
                }
                .buttonStyle(.primary)
                Button("Change the Date") { self.issue = nil }
                    .buttonStyle(.secondary)
            }

        case .higherThanLater(let later):
            IssuePanel(
                title: "Higher than a later reading",
                message: "Your reading of \(meter.dialText(later.value)) on \(DateText.short(later.date)) was taken after this date and is lower. Check the date or the number.",
                color: Palette.red
            ) {
                fixButton
                Button("Change the Date") { self.issue = nil }
                    .buttonStyle(.secondary)
            }

        case .exceedsDial(let maximum):
            IssuePanel(
                title: "More digits than the dial has",
                message: "This meter goes up to \(meter.dialText(maximum)). Check the number, or change the digit layout in the meter's settings.",
                color: Palette.red
            ) {
                fixButton
            }

        case .rolloverImplausible:
            IssuePanel(
                title: "That does not look like a roll-over",
                message: "A dial rolls over when it passes \(meter.dialText(meter.maximumValue)). The last reading was not near the top, or this one is not near zero.",
                color: Palette.red
            ) {
                Button("Choose Another Reason") {
                    dropReason = nil
                    attemptSave()
                }
                .buttonStyle(.secondary)
                fixButton
            }
        }
    }

    private var fixButton: some View {
        Button("Fix the Number") {
            issue = nil
            editing = true
            fieldFocused = true
        }
        .buttonStyle(.secondary)
    }

    private func choose(_ reason: DropReason, previous: Reading) {
        switch reason {
        case .typo:
            typoReadingIDs.append(previous.id)
            dropReason = .typo
        case .meterReplaced, .rolledOver:
            dropReason = reason
        }
        attemptSave()
    }

    private func resetChecks() {
        dropReason = nil
        typoReadingIDs = []
        acknowledgedUnusualRatio = nil
        acknowledgedSameDay = false
        if issue != nil { issue = nil }
    }

    // MARK: Save

    private func attemptSave() {
        guard let value else { return }
        fieldFocused = false
        let draft = ReadingDraft(
            meterID: meter.id,
            register: capture.register,
            date: date,
            value: value,
            dropReason: dropReason,
            acknowledgedUnusual: acknowledgedUnusualRatio != nil,
            acknowledgedSameDay: acknowledgedSameDay
        )
        if let found = ReadingValidator.firstIssue(for: draft, meter: meter, readings: store.state.readings, excluding: excluded) {
            issue = found
            return
        }

        var setAside: [UUID: String] = [:]
        for id in typoReadingIDs {
            setAside[id] = "Set aside as a typo when the reading of \(DateText.full(date)) was saved."
        }
        if acknowledgedSameDay {
            let day = ConsumptionEngine.day(date)
            for other in store.state.readings(for: meter.id, register: capture.register)
            where !other.isSetAside && ConsumptionEngine.day(other.date) == day && !excluded.contains(other.id) {
                setAside[other.id] = "Replaced by another reading the same day."
            }
        }

        var fileName: String?
        if let photo = capture.photo {
            do {
                fileName = try store.storePhoto(photo)
            } catch {
                store.errorMessage = "The photo could not be saved: \(error.localizedDescription)"
                return
            }
        }

        let typedOverRead = editing && capture.recognized != nil && value != capture.recognized?.value
        let source: ReadingSource
        if capture.photo == nil {
            source = .typed
        } else if capture.recognized != nil && !typedOverRead {
            source = .recognized
        } else {
            source = .typedWithPhoto
        }

        let reading = Reading(
            meterID: meter.id,
            register: capture.register,
            date: date,
            value: value,
            photoFile: fileName,
            source: source,
            dropReason: dropReason,
            confirmedUnusualRatio: acknowledgedUnusualRatio,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.addReading(reading, settingAside: setAside)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSaved(reading)
    }
}

/// A panel that stops the save and asks the user to choose.
struct IssuePanel<Actions: View>: View {
    let title: String
    let message: String
    var color: Color = Palette.red
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(color)
                Text(title)
                    .font(TypeScale.headline)
                    .foregroundStyle(Palette.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(message)
                .font(TypeScale.body)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                actions
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous).fill(Palette.panel))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
                .strokeBorder(color.opacity(0.8), lineWidth: Metrics.borderWidth)
        )
    }
}
