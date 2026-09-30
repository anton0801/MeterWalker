//
//  MeterWalkApp.swift
//  MeterWalk
//
//  Created by Anton Danilov on 22/9/26.
//

import SwiftUI

@main
struct MeterWalkApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Appearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Palette.yellow)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                store.flush()
            }
        }
    }
}

/// UIKit chrome in the app's colours.
enum Appearance {
    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Palette.background)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [
            .foregroundColor: UIColor(Palette.white),
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Palette.white)]
        let back = UIBarButtonItemAppearance()
        back.normal.titleTextAttributes = [.foregroundColor: UIColor(Palette.yellow)]
        nav.backButtonAppearance = back
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(Palette.yellow)

        UIDatePicker.appearance().tintColor = UIColor(Palette.yellow)
        UISwitch.appearance().onTintColor = UIColor(Palette.yellow)
    }
}
