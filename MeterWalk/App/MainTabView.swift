//
//  MainTabView.swift
//  MeterWalk
//
//  Four navigation stacks kept alive side by side under a custom tab bar,
//  with the scanner presented over everything from the centre button.
//

import SwiftUI

final class Router: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var homePath = NavigationPath()
    @Published var metersPath = NavigationPath()
    @Published var tariffsPath = NavigationPath()
    @Published var billsPath = NavigationPath()
    /// Non-nil while the scanner is open; carries the meter to start with.
    @Published var scan: ScanRequest?

    func openScanner(meterID: UUID? = nil) {
        scan = ScanRequest(meterID: meterID)
    }

    func show(_ tab: AppTab) {
        self.tab = tab
    }
}

struct ScanRequest: Identifiable, Equatable {
    let id = UUID()
    let meterID: UUID?
}

/// Places the app can push to.
enum Route: Hashable {
    case meter(UUID)
    case reading(UUID)
    case tariffReplay(UUID?)
    case tariff(UUID)
    case bill(UUID)
    case insights
    case appliances
    case settings
    case meters
    case tariffs
}

struct MainTabView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var router = Router()

    var body: some View {
        GeometryReader { proxy in
            let safeBottom = proxy.safeAreaInsets.bottom
            let barHeight = max(58, MeterTabBar.totalHeight - safeBottom)
            ZStack {
                stack(.home, path: $router.homePath) { HomeView() }
                stack(.meters, path: $router.metersPath) { MetersView() }
                stack(.tariffs, path: $router.tariffsPath) { TariffsView() }
                stack(.bills, path: $router.billsPath) { BillsView() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MeterTabBar(selection: $router.tab, contentHeight: barHeight) {
                    router.openScanner()
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environmentObject(router)
        .overlay(alignment: .top) {
            if let message = store.errorMessage {
                ErrorBanner(message: message) { store.errorMessage = nil }
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.standard, value: store.errorMessage)
        .onAppear(perform: applyDebugLaunch)
        .fullScreenCover(item: $router.scan) { request in
            ScanFlowView(initialMeterID: request.meterID) {
                router.scan = nil
            }
            .environmentObject(store)
        }
    }

    private func applyDebugLaunch() {
        if let tab = DebugLaunch.tab { router.tab = tab }
        if let route = DebugLaunch.route(in: store.state) {
            switch router.tab {
            case .home: router.homePath.append(route)
            case .meters: router.metersPath.append(route)
            case .tariffs: router.tariffsPath.append(route)
            case .bills: router.billsPath.append(route)
            }
        }
        if DebugLaunch.opensScanner { router.openScanner() }
    }

    private func stack<Content: View>(_ tab: AppTab, path: Binding<NavigationPath>, @ViewBuilder root: () -> Content) -> some View {
        let active = router.tab == tab
        return NavigationStack(path: path) {
            root()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        .opacity(active ? 1 : 0)
        .allowsHitTesting(active)
        .accessibilityHidden(!active)
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .meter(let id): MeterDetailView(meterID: id)
        case .reading(let id): ReadingDetailView(readingID: id)
        case .tariffReplay(let meterID): TariffReplayView(initialMeterID: meterID)
        case .tariff(let id): TariffDetailView(tariffID: id)
        case .bill(let id): BillDetailView(billID: id)
        case .insights: InsightsView()
        case .appliances: AppliancesView()
        case .settings: SettingsView()
        case .meters: MetersView(isRoot: false)
        case .tariffs: TariffsView(isRoot: false)
        }
    }
}
