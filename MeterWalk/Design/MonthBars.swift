//
//  MonthBars.swift
//  MeterWalk
//
//  Twelve months across the full width: this year in yellow with last year in
//  translucent blue beside it. Values are use per day, so months with
//  readings on odd dates still compare fairly. Bars grow from the bottom one
//  after another.
//

import SwiftUI

struct MonthBarsChart: View {
    let months: [ConsumptionEngine.MonthPair]
    var unit: String
    var height: CGFloat = 150
    var thisYearColor: Color = Palette.yellow

    @State private var grown = false
    @State private var selected: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maxValue: Double {
        let values = months.flatMap { [$0.thisYear?.dailyAverage, $0.lastYear?.dailyAverage] }.compactMap { $0 }
        return max(values.max() ?? 1, 0.0001)
    }

    private var hasRough: Bool { months.contains { $0.thisYear?.rough == true || $0.lastYear?.rough == true } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ZStack(alignment: .bottom) {
                gridLines
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(months.enumerated()), id: \.element.id) { index, pair in
                        column(pair, index: index)
                    }
                }
            }
            .frame(height: height)
            HStack(spacing: 4) {
                ForEach(months) { pair in
                    Text(DateText.monthLetter(pair.month))
                        .font(.system(size: 11, weight: selected == pair.month ? .bold : .medium))
                        .foregroundStyle(selected == pair.month ? Palette.yellow : Palette.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            legend
        }
        .onAppear {
            if reduceMotion {
                grown = true
            } else {
                grown = false
                DispatchQueue.main.async { grown = true }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if let selected, let pair = months.first(where: { $0.month == selected }) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(DateText.monthAndYear(pair.month))
                    .font(TypeScale.captionEmphasis)
                    .foregroundStyle(Palette.white)
                Spacer(minLength: 0)
                valueLabel(pair.thisYear?.dailyAverage, color: thisYearColor)
                valueLabel(pair.lastYear?.dailyAverage, color: Palette.blue, prefix: "last yr ")
            }
        } else {
            HStack {
                Text("\(unit) per day · tap a month")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.tertiaryText)
                Spacer()
                Text("max \(NumberText.rate(maxValue))")
                    .font(TypeScale.mono(12, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
    }

    private func valueLabel(_ value: Double?, color: Color, prefix: String = "") -> some View {
        Text(value.map { prefix + NumberText.rate($0) } ?? prefix + "—")
            .font(TypeScale.mono(13, weight: .semibold))
            .foregroundStyle(value == nil ? Palette.tertiaryText : color)
    }

    private var gridLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<4) { _ in
                Rectangle().fill(Palette.ghost.opacity(0.7)).frame(height: 1)
                Spacer(minLength: 0)
            }
            Rectangle().fill(Palette.ghost).frame(height: 1.5)
        }
    }

    private func column(_ pair: ConsumptionEngine.MonthPair, index: Int) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            bar(pair.lastYear, color: Palette.blue.opacity(0.4), index: index)
            bar(pair.thisYear, color: thisYearColor, index: index)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .bottom)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if selected == pair.month {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Palette.white.opacity(0.35), lineWidth: 1)
                    .padding(.horizontal, -1)
            }
        }
        .onTapGesture {
            withAnimation(Motion.standard) {
                selected = selected == pair.month ? nil : pair.month
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(DateText.monthAndYear(pair.month)))
        .accessibilityValue(Text(accessibilityValue(pair)))
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityValue(_ pair: ConsumptionEngine.MonthPair) -> String {
        let now = pair.thisYear?.dailyAverage.map { "\(NumberText.rate($0)) \(unit) a day" } ?? "no readings"
        let last = pair.lastYear?.dailyAverage.map { "last year \(NumberText.rate($0))" } ?? "no data last year"
        return "\(now), \(last)"
    }

    private func bar(_ use: MonthUse?, color: Color, index: Int) -> some View {
        let value = use?.dailyAverage ?? 0
        let barHeight = use == nil ? 2 : max(3, CGFloat(value / maxValue) * height)
        let fill: Color = use == nil ? Palette.ghost : (use!.rough ? color.opacity(0.5) : color)
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fill)
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
            .scaleEffect(x: 1, y: grown ? 1 : 0.001, anchor: .bottom)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.55).delay(Double(index) * Motion.barDelay), value: grown)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                legendItem(color: thisYearColor, text: "This year")
                legendItem(color: Palette.blue.opacity(0.4), text: "Last year")
            }
            if hasRough {
                Text("Paler bars come from readings more than 45 days apart, so they are rough.")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(TypeScale.caption).foregroundStyle(Palette.secondaryText)
        }
    }
}
