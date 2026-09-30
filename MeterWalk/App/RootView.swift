//
//  RootView.swift
//  MeterWalk
//
//  Loading → (error) → onboarding → the app.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var keptFileName: String?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            switch store.loadState {
            case .loading:
                launchScreen
            case .failed(let message):
                failure(message)
            case .loaded:
                if store.state.hasCompletedOnboarding {
                    MainTabView()
                        .transition(.opacity)
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
        }
        .animation(Motion.standard, value: store.loadState)
        .animation(Motion.standard, value: store.state.hasCompletedOnboarding)
        .task {
            if case .loading = store.loadState {
                await store.load()
            }
        }
    }

    private var launchScreen: some View {
        VStack(spacing: 18) {
            LCDReadout(text: "00000", size: 40, color: Palette.ghost, rollFromZero: false)
            Text("meter walk")
                .font(TypeScale.screenTitle)
                .tracking(-0.5)
                .foregroundStyle(Palette.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meter Walk is loading")
    }

    private func failure(_ message: String) -> some View {
        ScreenScroll {
            ScreenTitle("something went wrong")
            ErrorStatePanel(title: "Your data could not be opened", message: message) {
                Task { await store.load() }
            }
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If trying again does not help, you can start with an empty app. The unreadable file is renamed and kept in the app's storage, so nothing is deleted.")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Start Fresh and Keep the File") {
                        keptFileName = store.startFreshKeepingFile()
                    }
                    .buttonStyle(.destructive)
                    if let keptFileName {
                        AssumptionNote(text: "Kept as \(keptFileName).", symbol: "doc")
                    }
                }
            }
        }
    }
}
