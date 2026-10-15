//
//  OnboardingView.swift
//  MeterWalk
//
//  Four screens that explain, two that set up. No skipping and no demo
//  data: the app opens on the user's own first reading.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var page = 0
    @State private var electricity: ElectricityChoice = .none
    @State private var kinds: Set<MeterKind> = []
    @State private var digits: [MeterKind: DialLayout] = [:]
    @State private var onboardingMeterIDs: [UUID] = []
    @State private var scanningMeterID: UUID?
    @State private var firstReadingID: UUID?

    private let pageCount = 6

    enum ElectricityChoice: String, CaseIterable, Hashable {
        case none, single, twoRate

        var title: String {
            switch self {
            case .none: return "None"
            case .single: return "Single Rate"
            case .twoRate: return "Two Rate"
            }
        }

        var kind: MeterKind? {
            switch self {
            case .none: return nil
            case .single: return .electricitySingle
            case .twoRate: return .electricityTwoRate
            }
        }
    }

    struct DialLayout: Equatable {
        var before: Int
        var after: Int
    }

    private var selectedKinds: [MeterKind] {
        var result: [MeterKind] = []
        if let kind = electricity.kind { result.append(kind) }
        for kind in [MeterKind.gas, .waterCold, .waterHot] where kinds.contains(kind) {
            result.append(kind)
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 12)

            Group {
                switch page {
                case 0:
                    ExplainPage(
                        title: "The Bill Is Not the Meter",
                        text: "When nobody reads your meter, the supplier bills an estimate. It can run ahead of what you really used for months. Your own dated photo of the meter is the real number, and the proof if a bill is wrong.",
                        illustration: AnyView(BillVsMeterIllustration())
                    )
                case 1:
                    ExplainPage(
                        title: "Per Day, Not Per Bill",
                        text: "Readings are taken on different dates, so totals mislead: a 35-day bill looks worse than a 28-day one. Meter Walk divides the use between two readings by the days between them, and compares days with days.",
                        illustration: AnyView(PerDayIllustration())
                    )
                case 2:
                    ExplainPage(
                        title: "The Same kWh, a Different Price",
                        text: "Standing charges, day and night rates and tiers make the same use cost different amounts. Enter your tariff and the ones you might switch to; Meter Walk prices your real year on each, exit fees included.",
                        illustration: AnyView(SamePriceIllustration())
                    )
                case 3:
                    ExplainPage(
                        title: "One Photo a Month",
                        text: "One photo of each meter a month is enough. The numbers are read on this iPhone and you confirm them; the photo is kept as proof. No account and no network.",
                        illustration: AnyView(OnePhotoIllustration())
                    )
                case 4:
                    metersPage
                default:
                    firstReadingPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, page >= 4 ? 12 : 0)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(page)

            controls
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 12)
                .frame(maxWidth: Metrics.maxContentWidth)
        }
        .background(Palette.background.ignoresSafeArea())
        .onAppear {
            if let debugPage = DebugLaunch.onboardingPage { page = debugPage }
        }
        .fullScreenCover(item: Binding(
            get: { scanningMeterID.map { IdentifiedID(id: $0) } },
            set: { scanningMeterID = $0?.id }
        )) { item in
            ScanFlowView(initialMeterID: item.id, onClose: { scanningMeterID = nil }) { reading in
                firstReadingID = reading.id
            }
            .environmentObject(store)
        }
    }

    // MARK: Progress and controls

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= page ? Palette.yellow : Palette.ghost)
                    .frame(height: 4)
            }
        }
        .frame(maxWidth: Metrics.maxContentWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(page + 1) of \(pageCount)")
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            switch page {
            case 0...3:
                Button("Next") { advance() }
                    .buttonStyle(.primary)
            case 4:
                Button("Continue") {
                    createMeters()
                    advance()
                }
                .buttonStyle(.primary)
                .disabled(selectedKinds.isEmpty)
            default:
                if firstReadingID != nil {
                    Button("Open Meter Walk") { finish() }
                        .buttonStyle(.primary)
                } else {
                    Button("Photograph a Meter") { scanningMeterID = onboardingMeters.first?.id }
                        .buttonStyle(.primary)
                        .disabled(onboardingMeters.isEmpty)
                }
            }
            if page > 0 {
                Button("Back") { back() }
                    .buttonStyle(InlineButtonStyle(color: Palette.secondaryText))
                    .frame(height: 30)
            } else {
                Color.clear.frame(height: 30)
            }
        }
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.3)) { page = min(pageCount - 1, page + 1) }
    }

    private func back() {
        withAnimation(.easeInOut(duration: 0.3)) { page = max(0, page - 1) }
    }

    private func finish() {
        store.completeOnboarding()
        store.notifications.authorizationStatus { status in
            if status == .notDetermined {
                store.notifications.requestPermission { _ in
                    store.notifications.reschedule(state: store.state)
                }
            }
        }
    }

    // MARK: Your Meters

    private var metersPage: some View {
        ScreenScroll(spacing: 20) {
            ScreenTitle("your meters", subtitle: "Which meters do you read? You can add more, with serial numbers and suppliers, later.")

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Electricity")
                SegmentPicker(options: ElectricityChoice.allCases, selection: $electricity) { $0.title }
                Text(electricity == .twoRate
                     ? "A two-rate meter shows day (T1) and night (T2) separately. Both are read."
                     : "Two rate means the meter shows day and night counts separately.")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.tertiaryText)
                if let kind = electricity.kind {
                    dialPanel(kind)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Gas and water")
                ForEach([MeterKind.gas, .waterCold, .waterHot]) { kind in
                    VStack(spacing: 8) {
                        Panel(padding: 14) {
                            ToggleRow(
                                title: kind.title,
                                isOn: Binding(
                                    get: { kinds.contains(kind) },
                                    set: { on in
                                        if on { kinds.insert(kind) } else { kinds.remove(kind) }
                                    }
                                )
                            )
                        }
                        if kinds.contains(kind) {
                            dialPanel(kind)
                        }
                    }
                }
            }
        }
    }

    private func layout(_ kind: MeterKind) -> Binding<DialLayout> {
        Binding(
            get: { digits[kind] ?? DialLayout(before: kind.defaultDigitsBefore, after: kind.defaultDigitsAfter) },
            set: { digits[kind] = $0 }
        )
    }

    private func dialPanel(_ kind: MeterKind) -> some View {
        let binding = layout(kind)
        return Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(kind.defaultName) dial")
                        .font(TypeScale.captionEmphasis)
                        .foregroundStyle(Palette.secondaryText)
                    Spacer()
                    Text(MeterFormat.ghostText(before: binding.wrappedValue.before, after: binding.wrappedValue.after))
                        .font(TypeScale.mono(18))
                        .foregroundStyle(Palette.utility(kind.utility))
                }
                StepperRow(title: "Digits before the point", value: binding.before, range: 1...9)
                StepperRow(title: "Digits after the point", value: binding.after, range: 0...3)
            }
        }
    }

    /// Creates the chosen meters, reconciling with any made on an earlier
    /// pass through this page.
    private func createMeters() {
        var keep: [UUID] = []
        var toAdd: [MeterItem] = []
        let existing = onboardingMeterIDs.compactMap { store.state.meter($0) }

        for meter in existing {
            if selectedKinds.contains(meter.kind) {
                var updated = meter
                let dial = layout(meter.kind).wrappedValue
                updated.digitsBeforeDecimal = dial.before
                updated.digitsAfterDecimal = dial.after
                store.saveMeter(updated)
                keep.append(meter.id)
            } else if store.state.readings(for: meter.id).isEmpty {
                store.deleteMeter(meter.id)
            } else {
                keep.append(meter.id)
            }
        }
        let existingKinds = Set(existing.filter { keep.contains($0.id) }.map(\.kind))
        for kind in selectedKinds where !existingKinds.contains(kind) {
            var meter = MeterItem(kind: kind)
            let dial = layout(kind).wrappedValue
            meter.digitsBeforeDecimal = dial.before
            meter.digitsAfterDecimal = dial.after
            toAdd.append(meter)
        }
        store.addMeters(toAdd)
        onboardingMeterIDs = keep + toAdd.map(\.id)
    }

    private var onboardingMeters: [MeterItem] {
        onboardingMeterIDs.compactMap { store.state.meter($0) }
    }

    // MARK: Your First Reading

    private var firstReadingPage: some View {
        ScreenScroll(spacing: 20) {
            ScreenTitle("your first reading", subtitle: "Photograph one meter now. The app opens with its real reading.")

            if let id = firstReadingID,
               let reading = store.state.readings.first(where: { $0.id == id }),
               let meter = store.state.meter(reading.meterID) {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(meter.name, systemImage: meter.kind.symbol)
                            .font(TypeScale.bodyEmphasis)
                            .foregroundStyle(Palette.white)
                        RecessedDisplay {
                            FittedLCD(text: meter.dialText(reading.value), color: Palette.utility(meter.utility), unit: meter.unit)
                        }
                        Text("Saved \(DateText.full(reading.date)). Take the next one in about a month to see your first daily rate.")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if onboardingMeters.count > 1 {
                    Text("You can read your other meters now or later with the camera button.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(onboardingMeters) { meter in
                        Button { scanningMeterID = meter.id } label: {
                            Panel(padding: 14) {
                                HStack(spacing: 12) {
                                    Image(systemName: meter.kind.symbol)
                                        .foregroundStyle(Palette.utility(meter.utility))
                                        .frame(width: 30, height: 30)
                                        .background(RecessedShape())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meter.name)
                                            .font(TypeScale.bodyEmphasis)
                                            .foregroundStyle(Palette.white)
                                        Text(meter.ghostText)
                                            .font(TypeScale.mono(13))
                                            .foregroundStyle(Palette.ghost)
                                    }
                                    Spacer()
                                    Image(systemName: "camera.viewfinder")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(Palette.yellow)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                AssumptionNote(text: "Line up the number window in the frame. You check what was read before it is saved. If the camera cannot read it, type the number and the photo stays attached.")
            }
        }
    }
}

private struct IdentifiedID: Identifiable {
    let id: UUID
}

// MARK: - Explain page

private struct ExplainPage: View {
    let title: String
    let text: String
    let illustration: AnyView

    var body: some View {
        ScreenScroll(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous).fill(Palette.panel)
                CircuitTraces(seed: SeededRandom.stableSeed(title), density: 1.3)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous))
                illustration
                    .padding(20)
            }
            .frame(height: 280)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
                    .strokeBorder(Palette.ghost, lineWidth: Metrics.borderWidth)
            )
            .padding(.top, 12)

            ScreenTitle(title)
            Text(text)
                .font(TypeScale.body)
                .foregroundStyle(Palette.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
