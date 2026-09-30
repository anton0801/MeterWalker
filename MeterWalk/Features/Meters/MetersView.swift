//
//  MetersView.swift
//  MeterWalk
//

import SwiftUI

struct MetersView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    var isRoot = true
    @State private var addingMeter = false

    var body: some View {
        ScreenScroll(spacing: 20) {
            ScreenTitle(text: "meters", subtitle: subtitle) {
                IconButton(symbol: "plus", label: "Add meter", color: Palette.yellow) { addingMeter = true }
            }

            ListStateContainer {
                if store.state.meters.isEmpty {
                    EmptyStatePanel(
                        symbol: "speedometer",
                        title: "No meters yet",
                        message: "Add each meter you read: electricity, gas or water. Its digit layout tells the camera where the decimal point is.",
                        actionTitle: "Add a Meter"
                    ) { addingMeter = true }
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.state.meters) { meter in
                            NavigationLink(value: Route.meter(meter.id)) {
                                MeterSummaryPanel(meter: meter)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if store.loadState == .loaded, store.state.meters.contains(where: { $0.utility == .electricity }) {
                TitledSection(title: "Estimates") {
                    Panel(padding: 14) {
                        NavigationLink(value: Route.appliances) {
                            NavigationRowLabel(
                                symbol: "powerplug.fill",
                                title: "Appliance Estimates",
                                detail: store.state.appliances.isEmpty ? "None yet" : "\(store.state.appliances.count)",
                                tint: Palette.yellow
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(isRoot ? "" : "Meters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isRoot ? .hidden : .visible, for: .navigationBar)
        .sheet(isPresented: $addingMeter) {
            MeterEditorView(meter: nil)
        }
    }

    private var subtitle: String? {
        let count = store.state.meters.count
        guard count > 0 else { return nil }
        let readings = store.state.readings.filter { !$0.isSetAside }.count
        return "\(count) \(count == 1 ? "meter" : "meters") · \(readings) \(readings == 1 ? "reading" : "readings")"
    }
}
