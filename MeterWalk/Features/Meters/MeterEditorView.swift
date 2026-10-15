//
//  MeterEditorView.swift
//  MeterWalk
//
//  Add or edit a meter. The digit layout is shown as it will look on the
//  display, since that is what the camera uses to place the decimal point.
//

import SwiftUI

struct MeterEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let original: MeterItem?
    @State private var draft: MeterItem
    @State private var photo: UIImage?
    @State private var removedPhoto = false
    @State private var pickingPhoto = false
    @State private var takingPhoto = false
    @State private var choosingSource = false

    init(meter: MeterItem?) {
        original = meter
        _draft = State(initialValue: meter ?? MeterItem(kind: .electricitySingle))
    }

    private var hasReadings: Bool {
        guard let original else { return false }
        return !store.state.readings(for: original.id).isEmpty
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.unit.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        EditorSheet(
            title: original == nil ? "New Meter" : "Edit Meter",
            canSave: canSave,
            onCancel: { dismiss() },
            onSave: save
        ) {
            TextFieldBox(title: "Meter Name", text: $draft.name, placeholder: "Electricity")

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Type")
                if hasReadings {
                    Panel(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(draft.kind.title, systemImage: draft.kind.symbol)
                                .font(TypeScale.bodyEmphasis)
                                .foregroundStyle(Palette.white)
                            Text("The type cannot change once the meter has readings. Add a new meter instead.")
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.tertiaryText)
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        ForEach(MeterKind.allCases) { kind in
                            kindRow(kind)
                        }
                    }
                }
            }

            dialSection

            TextFieldBox(title: "Unit", text: $draft.unit, placeholder: draft.kind.defaultUnit, capitalization: .never)
            TextFieldBox(title: "Serial Number", text: $draft.serialNumber, placeholder: "Printed on the meter", capitalization: .characters)
            TextFieldBox(title: "Location", text: $draft.location, placeholder: "Hall cupboard")
            TextFieldBox(title: "Supplier", text: $draft.supplier, placeholder: "Who bills you")

            photoSection

            TextFieldBox(title: "Notes", text: $draft.notes, placeholder: "Optional", capitalization: .sentences, axis: .vertical)
        }
        .sheet(isPresented: $pickingPhoto) {
            PhotoLibraryPicker { image, _ in
                pickingPhoto = false
                if let image { photo = image; removedPhoto = false }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $takingPhoto) {
            SystemCameraPicker { image in
                takingPhoto = false
                if let image { photo = image; removedPhoto = false }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("Meter Photo", isPresented: $choosingSource) {
            if SystemCameraPicker.isAvailable {
                Button("Take Photo") { takingPhoto = true }
            }
            Button("Choose Photo") { pickingPhoto = true }
        }
    }

    private func kindRow(_ kind: MeterKind) -> some View {
        let selected = draft.kind == kind
        return Button {
            let unitWasDefault = draft.unit == draft.kind.defaultUnit
            let digitsWereDefault = draft.digitsAfterDecimal == draft.kind.defaultDigitsAfter
            let nameWasDefault = draft.name == draft.kind.defaultName || draft.name.isEmpty
            draft.kind = kind
            if unitWasDefault { draft.unit = kind.defaultUnit }
            if digitsWereDefault { draft.digitsAfterDecimal = kind.defaultDigitsAfter }
            if nameWasDefault { draft.name = kind.defaultName }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .foregroundStyle(Palette.utility(kind.utility))
                    .frame(width: 22)
                Text(kind.title)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.white)
                Spacer()
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Palette.yellow : Palette.ghost)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RecessedShape())
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.displayRadius)
                    .strokeBorder(selected ? Palette.yellow.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var dialSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(text: "Dial Layout", hint: "as printed on the meter")
            Panel(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    RecessedDisplay {
                        FittedLCD(
                            text: draft.ghostText,
                            maxSize: 40,
                            color: Palette.utility(draft.utility).opacity(0.35),
                            rollFromZero: false
                        )
                    }
                    StepperRow(title: "Digits Before Decimal", value: $draft.digitsBeforeDecimal, range: 1...9)
                    StepperRow(title: "Digits After Decimal", value: $draft.digitsAfterDecimal, range: 0...3)
                    Text("Count the drums or LCD digits. Fraction digits are often red or boxed. The camera uses this to tell the whole number from the fraction.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Photo", hint: "the whole meter, for reference")
            HStack(spacing: 12) {
                if let photo {
                    Image(uiImage: photo)
                        .resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if !removedPhoto, draft.photoFile != nil {
                    PhotoThumb(fileName: draft.photoFile, size: 64)
                }
                Button(hasPhoto ? "Replace Photo" : "Add Photo") { choosingSource = true }
                    .buttonStyle(InlineButtonStyle())
                if hasPhoto {
                    Button("Remove") {
                        photo = nil
                        removedPhoto = true
                    }
                    .buttonStyle(InlineButtonStyle(color: Palette.red))
                }
                Spacer()
            }
        }
    }

    private var hasPhoto: Bool { photo != nil || (!removedPhoto && draft.photoFile != nil) }

    private func save() {
        var meter = draft
        meter.name = meter.name.trimmingCharacters(in: .whitespacesAndNewlines)
        meter.unit = meter.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if let photo {
            do {
                let name = try store.storePhoto(photo)
                store.discardPhoto(original?.photoFile)
                meter.photoFile = name
            } catch {
                store.errorMessage = "The photo could not be saved: \(error.localizedDescription)"
            }
        } else if removedPhoto {
            store.discardPhoto(original?.photoFile)
            meter.photoFile = nil
        }
        store.saveMeter(meter)
        dismiss()
    }
}
