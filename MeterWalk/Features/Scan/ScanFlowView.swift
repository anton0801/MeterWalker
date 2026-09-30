//
//  ScanFlowView.swift
//  MeterWalk
//
//  Choose a meter → photograph the number window → check what was read →
//  saved. Two-rate meters go through the day register, then the night one.
//

import SwiftUI

struct ScanFlowView: View {
    let initialMeterID: UUID?
    let onClose: () -> Void
    /// Called after each reading is saved (onboarding waits for the first).
    var onSaved: ((Reading) -> Void)? = nil

    @EnvironmentObject private var store: AppStore
    @State private var step: Step = .chooseMeter

    enum Step: Equatable {
        case chooseMeter
        case capture(meterID: UUID, register: Register)
        case review(Capture)
        case saved(readingID: UUID)
    }

    /// Everything the review screen needs from the capture.
    struct Capture: Equatable {
        let id = UUID()
        let meterID: UUID
        let register: Register
        let photo: UIImage?
        let photoDate: Date?
        let recognized: RecognizedReading?
        /// True when a photo was taken but nothing could be read from it.
        let recognitionFailed: Bool
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            switch step {
            case .chooseMeter:
                MeterChooser(onClose: onClose) { meter in
                    go(.capture(meterID: meter.id, register: meter.registers[0]))
                }
                .transition(.opacity)
            case .capture(let meterID, let register):
                if let meter = store.state.meter(meterID) {
                    CameraCaptureView(
                        meter: meter,
                        register: register,
                        onClose: onClose,
                        onCaptured: { capture in go(.review(capture)) }
                    )
                    .transition(.opacity)
                }
            case .review(let capture):
                if let meter = store.state.meter(capture.meterID) {
                    ReviewReadingView(
                        meter: meter,
                        capture: capture,
                        onBack: { go(.capture(meterID: capture.meterID, register: capture.register)) },
                        onClose: onClose,
                        onSaved: { reading in
                            onSaved?(reading)
                            go(.saved(readingID: reading.id))
                        }
                    )
                    .transition(.opacity)
                }
            case .saved(let readingID):
                if let reading = store.state.readings.first(where: { $0.id == readingID }),
                   let meter = store.state.meter(reading.meterID) {
                    SavedReadingView(
                        meter: meter,
                        reading: reading,
                        onNextRegister: { register in go(.capture(meterID: meter.id, register: register)) },
                        onAnotherMeter: store.state.meters.count > 1 ? { go(.chooseMeter) } : nil,
                        onDone: onClose
                    )
                    .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: chooseStart)
    }

    private func go(_ next: Step) {
        withAnimation(Motion.standard) { step = next }
    }

    private func chooseStart() {
        guard step == .chooseMeter else { return }
        #if DEBUG
        if let capture = DebugLaunch.reviewCapture(meter: store.state.meters.first) {
            step = .review(capture)
            return
        }
        #endif
        if let id = initialMeterID, let meter = store.state.meter(id) {
            step = .capture(meterID: meter.id, register: meter.registers[0])
        } else if store.state.meters.count == 1, let meter = store.state.meters.first {
            step = .capture(meterID: meter.id, register: meter.registers[0])
        }
    }
}

// MARK: - Meter chooser

private struct MeterChooser: View {
    @EnvironmentObject private var store: AppStore
    let onClose: () -> Void
    let onChoose: (Meter) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                IconButton(symbol: "xmark", label: "Close", action: onClose)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)

            ScreenScroll(spacing: 16) {
                ScreenTitle("which meter?", subtitle: "Pick the meter you are standing at.")
                if store.state.meters.isEmpty {
                    EmptyStatePanel(
                        symbol: "speedometer",
                        title: "No meters yet",
                        message: "Add a meter from the Meters tab first, with its digit layout, so the camera knows where the decimal point is."
                    )
                }
                ForEach(store.state.meters) { meter in
                    Button { onChoose(meter) } label: {
                        MeterSummaryPanel(meter: meter, compact: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Saved

struct SavedReadingView: View {
    @EnvironmentObject private var store: AppStore
    let meter: Meter
    let reading: Reading
    let onNextRegister: (Register) -> Void
    let onAnotherMeter: (() -> Void)?
    let onDone: () -> Void

    private var interval: UseInterval? {
        ConsumptionEngine.intervals(meter: meter, register: reading.register, readings: store.state.readings)
            .first { $0.endReadingID == reading.id }
    }

    private var nextRegister: Register? {
        guard meter.kind.isTwoRate, reading.register == .day else { return nil }
        // Only ask for the night register if it has not been read today.
        let today = ConsumptionEngine.day(reading.date)
        let hasNight = store.state.readings(for: meter.id, register: .night)
            .contains { !$0.isSetAside && ConsumptionEngine.day($0.date) == today }
        return hasNight ? nil : .night
    }

    var body: some View {
        ScreenScroll(spacing: 20) {
            Spacer(minLength: 24)
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.yellow)
                Text("reading saved")
                    .font(TypeScale.screenTitle)
                    .tracking(-0.5)
                    .foregroundStyle(Palette.white)
            }

            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(meter.name, systemImage: meter.kind.symbol)
                            .font(TypeScale.bodyEmphasis)
                            .foregroundStyle(Palette.white)
                        Spacer()
                        if reading.register != .total {
                            Badge(text: "\(reading.register.title) \(reading.register.meterLabel)", color: Palette.utility(meter.utility))
                        }
                    }
                    RecessedDisplay {
                        FittedLCD(text: meter.dialText(reading.value), color: Palette.utility(meter.utility), unit: meter.unit)
                    }
                    Text("\(DateText.full(reading.date)) at \(DateText.clock(reading.date)) · \(reading.source.title)")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }
            }

            if let interval {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Per day since last reading")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(NumberText.rate(interval.dailyRate))
                                .font(TypeScale.money)
                                .foregroundStyle(Palette.white)
                            Text("\(meter.unit) a day")
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Text("\(NumberText.use(interval.use)) \(meter.unit) over \(DateText.days(interval.days)) since \(DateText.short(interval.startDay)).")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.secondaryText)
                        if interval.isRough {
                            AssumptionNote(text: "Rough: more than 45 days between readings, so the daily figure is an average over a long stretch.", symbol: "exclamationmark.circle")
                        }
                        if interval.rolledOver {
                            AssumptionNote(text: "Counted across the dial rolling over.", symbol: "arrow.clockwise")
                        }
                    }
                }
            } else {
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader("Daily use")
                        Text(firstReadingText)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(spacing: 12) {
                if let nextRegister {
                    Button("Next: \(nextRegister.title) Register \(nextRegister.meterLabel)") { onNextRegister(nextRegister) }
                        .buttonStyle(.primary)
                    Button("Done", action: onDone)
                        .buttonStyle(.secondary)
                } else {
                    Button("Done", action: onDone)
                        .buttonStyle(.primary)
                    if let onAnotherMeter {
                        Button("Scan Another Meter", action: onAnotherMeter)
                            .buttonStyle(.secondary)
                    }
                }
            }
        }
    }

    private var firstReadingText: String {
        if reading.dropReason == .meterReplaced {
            return "This starts the new meter. The next reading gives its first daily rate."
        }
        return "This is the first reading here. The next one, a few weeks from now, gives your first daily rate."
    }
}
