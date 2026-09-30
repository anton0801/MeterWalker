//
//  FormControls.swift
//  MeterWalk
//
//  Inputs sit in recessed LCD windows. Numbers are typed in yellow mono, the
//  way the meter shows them.
//

import SwiftUI

struct FieldLabel: View {
    let text: String
    var hint: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(TypeScale.captionEmphasis)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 8)
            if let hint {
                Text(hint)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
    }
}

struct TextFieldBox: View {
    let title: String
    @Binding var text: String
    var placeholder = ""
    var hint: String? = nil
    var capitalization: TextInputAutocapitalization = .words
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title, hint: hint)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Palette.tertiaryText), axis: axis)
                .font(TypeScale.body)
                .foregroundStyle(Palette.white)
                .textInputAutocapitalization(capitalization)
                .lineLimit(axis == .vertical ? 3...8 : 1...1)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(RecessedShape())
                .accessibilityLabel(title)
        }
    }
}

struct NumberFieldBox: View {
    let title: String
    @Binding var text: String
    var unit: String? = nil
    var placeholder = "0"
    var hint: String? = nil
    var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title, hint: hint)
            HStack(spacing: 8) {
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Palette.ghost))
                    .font(TypeScale.mono(20))
                    .foregroundStyle(Palette.yellow)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel(title)
                if let unit {
                    Text(unit)
                        .font(TypeScale.captionEmphasis)
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RecessedShape())
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.displayRadius)
                    .strokeBorder(Palette.red, lineWidth: invalid ? 1.5 : 0)
            )
        }
    }
}

/// Horizontal set of options in an LCD strip; the active one is lit yellow.
struct SegmentPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let active = option == selection
                Button {
                    withAnimation(Motion.standard) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(active ? Palette.background : Palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(active ? Palette.yellow : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RecessedShape(radius: 8))
    }
}

struct ToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.white)
                if let detail {
                    Text(detail)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Palette.yellow)
    }
}

struct DateRow: View {
    let title: String
    @Binding var date: Date
    var components: DatePickerComponents = [.date]
    var range: ClosedRange<Date>? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(TypeScale.body)
                .foregroundStyle(Palette.white)
            Spacer()
            Group {
                if let range {
                    DatePicker("", selection: $date, in: range, displayedComponents: components)
                } else {
                    DatePicker("", selection: $date, displayedComponents: components)
                }
            }
            .labelsHidden()
            .tint(Palette.yellow)
            .accessibilityLabel(title)
        }
    }
}

struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var display: ((Int) -> String)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(TypeScale.body)
                .foregroundStyle(Palette.white)
            Spacer()
            Text(display?(value) ?? "\(value)")
                .font(TypeScale.mono(18))
                .foregroundStyle(Palette.yellow)
                .frame(minWidth: 28)
            HStack(spacing: 0) {
                stepButton("minus", enabled: value > range.lowerBound) { value -= 1 }
                Rectangle().fill(Palette.ghost).frame(width: 1, height: 20)
                stepButton("plus", enabled: value < range.upperBound) { value += 1 }
            }
            .background(RecessedShape(radius: 8))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(display?(value) ?? "\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { value += 1 }
            case .decrement: if value > range.lowerBound { value -= 1 }
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? Palette.white : Palette.ghost)
                .frame(width: 40, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// A modal editor: its own navigation bar with Cancel and a primary action.
struct EditorSheet<Content: View>: View {
    let title: String
    var saveTitle = "Save"
    var canSave = true
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: 20) {
                content
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(Palette.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle, action: onSave)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(canSave ? Palette.yellow : Palette.tertiaryText)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .foregroundStyle(Palette.yellow)
                }
            }
        }
        .sheetBackground()
    }
}

extension View {
    /// Navy behind a sheet. `presentationBackground` exists from iOS 16.4;
    /// earlier the sheet shows the navy of its own content.
    @ViewBuilder
    func sheetBackground() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(Palette.background)
        } else {
            self
        }
    }
}
