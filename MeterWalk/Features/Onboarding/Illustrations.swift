//
//  Illustrations.swift
//  MeterWalk
//
//  Onboarding pictures built from the app's own parts: LCD windows, the
//  dial and the bars. The numbers are illustrative only and are never saved.
//

import SwiftUI

struct BillVsMeterIllustration: View {
    var body: some View {
        VStack(spacing: 14) {
            labelledDisplay(label: "ON THE BILL · ESTIMATED", text: "04350", color: Palette.white)
            labelledDisplay(label: "YOUR PHOTO · SAME DAY", text: "04211", color: Palette.yellow)
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("139 kWh billed, not used")
            }
            .font(TypeScale.bodyEmphasis)
            .foregroundStyle(Palette.red)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A bill estimate of 04350 next to a meter photo showing 04211: 139 kilowatt hours billed but not used.")
    }

    private func labelledDisplay(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Palette.blue)
            RecessedDisplay(verticalPadding: 6) {
                LCDReadout(text: text, size: 34, color: color, unit: "kWh")
            }
        }
    }
}

struct PerDayIllustration: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .bottom) {
                pin(date: "12 Aug", value: "04120")
                Spacer()
                VStack(spacing: 4) {
                    Text("31 days")
                        .font(TypeScale.captionEmphasis)
                        .foregroundStyle(Palette.secondaryText)
                    Rectangle().fill(Palette.ghost).frame(height: 2)
                }
                .frame(maxWidth: 90)
                .padding(.bottom, 24)
                Spacer()
                pin(date: "12 Sep", value: "04430")
            }
            RecessedDisplay(verticalPadding: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("310 ÷ 31 =")
                        .font(TypeScale.mono(16, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                    LCDReadout(text: "10.0", size: 34)
                    Text("kWh/day")
                        .font(TypeScale.captionEmphasis)
                        .foregroundStyle(Palette.yellow.opacity(0.8))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Two readings 31 days apart: 310 kilowatt hours divided by 31 days is 10 a day.")
    }

    private func pin(date: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(TypeScale.mono(17))
                .foregroundStyle(Palette.yellow)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RecessedShape())
            Circle().fill(Palette.yellow).frame(width: 10, height: 10)
            Text(date)
                .font(TypeScale.captionEmphasis)
                .foregroundStyle(Palette.white)
        }
    }
}

struct SamePriceIllustration: View {
    private let columns: [(String, Double, Bool)] = [("Flat", 1.0, false), ("Two Rate", 0.87, true), ("Tiered", 0.94, false)]
    @State private var grown = false

    var body: some View {
        VStack(spacing: 14) {
            RecessedDisplay(verticalPadding: 6) {
                HStack {
                    Text("SAME USE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Palette.blue)
                    Spacer()
                    LCDReadout(text: "3650", size: 26, unit: "kWh")
                }
            }
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(column.2 ? Palette.yellow : Palette.blue.opacity(0.4))
                            .frame(height: 120 * column.1)
                            .scaleEffect(x: 1, y: grown ? 1 : 0.01, anchor: .bottom)
                            .animation(.easeOut(duration: 0.55).delay(Double(index) * Motion.barDelay + 0.2), value: grown)
                        Text(column.0)
                            .font(TypeScale.captionEmphasis)
                            .foregroundStyle(column.2 ? Palette.yellow : Palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 145, alignment: .bottom)
        }
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The same 3650 kilowatt hours priced on three tariffs, each giving a different total.")
    }
}

struct OnePhotoIllustration: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RecessedDisplay(verticalPadding: 10) {
                    LCDReadout(text: "04182.6", size: 34)
                        .frame(maxWidth: .infinity)
                }
                .padding(10)
                Corners()
                    .stroke(Palette.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 90)

            HStack(spacing: 6) {
                ForEach(0..<12, id: \.self) { month in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(month < 9 ? Palette.yellow : Palette.ghost)
                            .frame(width: 10, height: 10)
                        Text(monthLetter(month))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A camera frame around a meter reading, and one photo a month through the year.")
    }

    private func monthLetter(_ index: Int) -> String {
        let symbols = DateFormatter().veryShortMonthSymbols ?? []
        return index < symbols.count ? symbols[index] : ""
    }

    private struct Corners: Shape {
        func path(in rect: CGRect) -> Path {
            let arm: CGFloat = 18
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + arm)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
            p.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
            p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
            p.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
            return p
        }
    }
}
