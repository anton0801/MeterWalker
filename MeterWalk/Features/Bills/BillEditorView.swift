//
//  BillEditorView.swift
//  MeterWalk
//
//  A bill: its period, the readings printed on it and what it charged.
//  The amount and dates can be read from a photo of the bill, on the device,
//  but the bill is not saved until the user has checked them.
//

import SwiftUI

struct BillEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let original: Bill?
    @State private var draft: Bill
    @State private var amount: String
    @State private var readingText: [Register: (opening: String, closing: String)]
    @State private var photo: UIImage?
    @State private var removedPhoto = false
    @State private var choosingSource = false
    @State private var pickingPhoto = false
    @State private var takingPhoto = false
    @State private var recognizing = false
    /// What was read from the photo, waiting for the user to check it.
    @State private var recognized: RecognizedBill?
    @State private var recognizedChecked = false

    init(bill: Bill?, meterID: UUID? = nil) {
        original = bill
        let now = Date()
        let base = bill ?? Bill(
            meterID: meterID,
            periodFrom: ConsumptionEngine.addMonths(-1, to: ConsumptionEngine.day(now)),
            periodTo: ConsumptionEngine.day(now)
        )
        _draft = State(initialValue: base)
        _amount = State(initialValue: bill.map { NumberText.editable($0.amount) } ?? "")
        var texts: [Register: (String, String)] = [:]
        for register in Register.allCases {
            let r = base.readings(for: register)
            texts[register] = (NumberText.editable(r?.opening), NumberText.editable(r?.closing))
        }
        _readingText = State(initialValue: texts.mapValues { (opening: $0.0, closing: $0.1) })
    }

    private var meter: MeterItem? { store.state.meter(draft.meterID) }
    private var registers: [Register] { meter?.registers ?? [.total] }

    private func binding(_ register: Register, opening: Bool) -> Binding<String> {
        Binding(
            get: {
                let pair = readingText[register] ?? (opening: "", closing: "")
                return opening ? pair.opening : pair.closing
            },
            set: { value in
                var pair = readingText[register] ?? (opening: "", closing: "")
                if opening { pair.opening = value } else { pair.closing = value }
                readingText[register] = pair
            }
        )
    }

    private var problems: [String] {
        var result: [String] = []
        if NumberText.parse(amount) == nil { result.append("Enter the amount on the bill.") }
        if draft.periodTo <= draft.periodFrom { result.append("The period must end after it starts.") }
        for register in registers {
            let pair = readingText[register] ?? (opening: "", closing: "")
            if !pair.opening.isEmpty && NumberText.parse(pair.opening) == nil { result.append("A reading on the bill is not a number.") }
            if !pair.closing.isEmpty && NumberText.parse(pair.closing) == nil { result.append("A reading on the bill is not a number.") }
            if let o = NumberText.parse(pair.opening), let c = NumberText.parse(pair.closing), c < o {
                result.append("The closing reading is lower than the opening one.")
            }
        }
        if recognized != nil && !recognizedChecked {
            result.append("Check the values read from the photo against the bill, then tick the box.")
        }
        return Array(NSOrderedSet(array: result)) as? [String] ?? result
    }

    var body: some View {
        EditorSheet(
            title: original == nil ? "New Bill" : "Edit Bill",
            canSave: problems.isEmpty,
            onCancel: {
                dismiss()
            },
            onSave: save
        ) {
            photoSection

            if let recognized {
                recognizedPanel(recognized)
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Meter", hint: "needed for the bill check")
                if store.state.meters.isEmpty {
                    Text("Add a meter first to check this bill against your readings.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.tertiaryText)
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.state.meters) { meter in
                            meterOption(meter)
                        }
                    }
                }
            }

            TextFieldBox(title: "Supplier", text: $draft.supplier, placeholder: meter?.supplier.isEmpty == false ? meter!.supplier : "Who sent the bill")

            Panel(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    DateRow(title: "Period From", date: $draft.periodFrom)
                    Divider2()
                    DateRow(title: "Period To", date: $draft.periodTo)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Reading Type on Bill")
                SegmentPicker(options: BillReadingType.allCases, selection: $draft.readingType) { $0.title }
                Text(draft.readingType.explanation + (draft.readingType == .estimated ? " Often marked E next to the reading." : ""))
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }

            ForEach(registers) { register in
                VStack(alignment: .leading, spacing: 8) {
                    if register != .total {
                        SectionHeader("\(register.title) register \(register.meterLabel)")
                    }
                    HStack(spacing: 10) {
                        NumberFieldBox(title: "Opening Reading on Bill", text: binding(register, opening: true), placeholder: meter?.dialText(0) ?? "0")
                        NumberFieldBox(title: "Closing Reading on Bill", text: binding(register, opening: false), placeholder: meter?.dialText(0) ?? "0")
                    }
                }
            }

            NumberFieldBox(title: "Amount", text: $amount, unit: store.money.symbol, placeholder: "0.00")

            TextFieldBox(title: "Notes", text: $draft.notes, placeholder: "Optional", capitalization: .sentences, axis: .vertical)

            if !problems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(problems, id: \.self) { problem in
                        AssumptionNote(text: problem, symbol: "exclamationmark.circle", color: Palette.tertiaryText)
                    }
                }
            }
        }
        .sheet(isPresented: $pickingPhoto) {
            PhotoLibraryPicker { image, _ in
                pickingPhoto = false
                if let image { use(image) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $takingPhoto) {
            SystemCameraPicker { image in
                takingPhoto = false
                if let image { use(image) }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("Bill Photo", isPresented: $choosingSource) {
            if SystemCameraPicker.isAvailable {
                Button("Photograph the Bill") { takingPhoto = true }
            }
            Button("Choose Photo") { pickingPhoto = true }
        }
    }

    // MARK: Photo

    private var hasPhoto: Bool { photo != nil || (!removedPhoto && draft.photoFile != nil) }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Bill Photo", hint: "the amount and dates can be read from it")
            HStack(spacing: 12) {
                if let photo {
                    Image(uiImage: photo)
                        .resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if !removedPhoto, draft.photoFile != nil {
                    PhotoThumb(fileName: draft.photoFile, size: 64)
                }
                if recognizing {
                    ProgressView().tint(Palette.yellow)
                    Text("Reading the bill…")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.secondaryText)
                } else {
                    Button(hasPhoto ? "Replace Photo" : "Add Photo") { choosingSource = true }
                        .buttonStyle(InlineButtonStyle())
                    if hasPhoto {
                        Button("Remove") {
                            photo = nil
                            removedPhoto = true
                            recognized = nil
                        }
                        .buttonStyle(InlineButtonStyle(color: Palette.red))
                    }
                }
                Spacer()
            }
        }
    }

    private func use(_ image: UIImage) {
        photo = image
        removedPhoto = false
        recognizing = true
        BillRecognizer.recognize(image: image) { result in
            recognizing = false
            guard !result.isEmpty else {
                recognized = nil
                store.errorMessage = nil
                return
            }
            if let value = result.amount { amount = NumberText.editable(value) }
            if let from = result.periodFrom { draft.periodFrom = from }
            if let to = result.periodTo { draft.periodTo = to }
            recognized = result
            recognizedChecked = false
        }
    }

    private func recognizedPanel(_ result: RecognizedBill) -> some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Read from the photo")
                if let value = result.amount {
                    KeyValueRow(key: "Amount", value: store.money.exact(value), valueColor: Palette.yellow, mono: true)
                }
                if let from = result.periodFrom, let to = result.periodTo {
                    KeyValueRow(key: "Period", value: "\(DateText.full(from)) – \(DateText.full(to))", valueColor: Palette.yellow)
                } else if let from = result.periodFrom {
                    KeyValueRow(key: "Date", value: DateText.full(from), valueColor: Palette.yellow)
                }
                Text("These are filled in below. Photos of bills are often misread, so compare each one with the paper.")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ToggleRow(title: "I checked these against the bill", isOn: $recognizedChecked)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.panelRadius)
                .strokeBorder(recognizedChecked ? Color.clear : Palette.yellow.opacity(0.6), lineWidth: 2)
        )
    }

    private func meterOption(_ meter: MeterItem) -> some View {
        let selected = draft.meterID == meter.id
        return Button {
            draft.meterID = selected ? nil : meter.id
            if draft.supplier.isEmpty { draft.supplier = meter.supplier }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: meter.kind.symbol)
                    .foregroundStyle(Palette.utility(meter.utility))
                    .frame(width: 22)
                Text(meter.name)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.white)
                Spacer()
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Palette.yellow : Palette.ghost)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RecessedShape())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Save

    private func save() {
        guard problems.isEmpty, let value = NumberText.parse(amount) else { return }
        var bill = draft
        bill.amount = value
        bill.supplier = bill.supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        bill.readings = registers.compactMap { register in
            let pair = readingText[register] ?? (opening: "", closing: "")
            let opening = NumberText.parse(pair.opening)
            let closing = NumberText.parse(pair.closing)
            guard opening != nil || closing != nil else { return nil }
            return BillRegisterReadings(register: register, opening: opening, closing: closing)
        }
        if let photo {
            do {
                let name = try store.storePhoto(photo)
                store.discardPhoto(original?.photoFile)
                bill.photoFile = name
            } catch {
                store.errorMessage = "The bill photo could not be saved: \(error.localizedDescription)"
            }
        } else if removedPhoto {
            store.discardPhoto(original?.photoFile)
            bill.photoFile = nil
        }
        store.saveBill(bill)
        dismiss()
    }
}
