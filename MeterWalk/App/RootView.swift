import SwiftUI
import Network

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var keptFileName: String?
    
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var surveyor = Surveyor()

    private var mainContent: some View {
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
        .onAppear {
            Appearance.apply()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                store.flush()
            }
        }
        .tint(Palette.yellow)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                launchScreen
                
                NavigationLink(
                    destination: PaneView().navigationBarHidden(true),
                    isActive: $surveyor.navigateToWeb
                ) { EmptyView() }

                NavigationLink(
                    destination: mainContent.navigationBarBackButtonHidden(true),
                    isActive: $surveyor.navigateToMain
                ) { EmptyView() }
            }
            .fullScreenCover(isPresented: $surveyor.showPermissionPrompt) {
                consent
            }
            .onReceive(NotificationCenter.default.publisher(for: .veered)) { note in
                guard let bag = note.userInfo?["deeplinksData"] as? [String: Any] else { return }
                surveyor.absorbDeeplinks(bag.mapValues { "\($0)" })
            }
           .fullScreenCover(isPresented: $surveyor.showOfflineView) {
               offline
           }
           .onReceive(NotificationCenter.default.publisher(for: .strode)) { note in
               guard let bag = note.userInfo?["conversionData"] as? [String: Any] else { return }
               surveyor.absorbConversion(bag.mapValues { "\($0)" })
           }
           .onAppear(perform: stride)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    @State private var monitor = NWPathMonitor()
    
    private var launchScreen: some View {
        GeometryReader { geo in
            ZStack {
                Image("app loading background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                
                VStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(.blue)
                            .frame(width: 128, height: 128)
                        
                        Image("icon")
                            .resizable()
                            .frame(width: 120, height: 120)
                            .cornerRadius(32)
                    }
                    
                    MeterWalkerLoader()
                    
                    Image("app loading icon")
                        .resizable()
                        .frame(width: 200, height: 50)
                }
                
            }
        }
        .ignoresSafeArea()
    }
    
    private func stride() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in surveyor.networkChanged(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        surveyor.ignite()
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
    
    var consent: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                Image("app suc")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.95)
                    .ignoresSafeArea()
                
                if wide {
                    contesentViewWide
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        VStack(spacing: 12) {
                            Text("ALLOW NOTIFICATIONS АВОUT\nВОNUSЕS АND РRОМОS")
                                .font(.system(size: 23, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            
                            Text("STAY TUNED WITH ВЕST ОFFЕRS FRОМ\nОUR САSINО")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .opacity(0.7)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        
                        VStack(spacing: 12) {
                            Button { surveyor.acceptConsent() } label: {
                                Image("app ss")
                                    .resizable()
                                    .frame(width: 300, height: 55)
                            }
                            Button { surveyor.skipConsent() } label: {
                                Image("app spl")
                                    .resizable()
                                    .frame(width: 280, height: 37)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.bottom, 28)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
    
    private var contesentViewWide: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("ALLOW NOTIFICATIONS АВОUT\nВОNUSЕS АND РRОМОS")
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("STAY TUNED WITH ВЕST ОFFЕRS FRОМ\nОUR САSINО")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(0.7)
                }
                .multilineTextAlignment(.leading)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button { surveyor.acceptConsent() } label: {
                        Image("app ss")
                            .resizable()
                            .frame(width: 300, height: 55)
                    }
                    Button { surveyor.skipConsent() } label: {
                        Image("app spl")
                            .resizable()
                            .frame(width: 280, height: 37)
                    }
                }
                
                Spacer()
            }
            .padding(.bottom, 28)
        }
    }
    
    var offline: some View {
        GeometryReader { geo in
            ZStack {
                Image("application error background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                
                Image("app error alert")
                    .resizable()
                    .frame(width: 270, height: 270)
            }
        }
        .ignoresSafeArea()
    }
    
}

struct MeterWalkerLoader: View {
    private let title: String
    private let tint: Color
    private let textColor: Color
    private let fontSize: CGFloat

    @State private var isRunning = false
    @State private var startDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Следы
    private let stepCount = 6
    private let stepPeriod: Double = 1.8
    // Буквы
    private let letterPeriod: Double = 1.6
    private let letterDelay: Double = 0.06

    init(
        title: String = "Meter Walker",
        tint: Color = .accentColor,
        textColor: Color = .primary,
        fontSize: CGFloat = 34
    ) {
        self.title = title
        self.tint = tint
        self.textColor = textColor
        self.fontSize = fontSize
    }

    var body: some View {
        TimelineView(.animation(paused: !isRunning)) { context in
            let t = context.date.timeIntervalSince(startDate)

            VStack(spacing: 22) {
                HStack(spacing: 6) {
                    ForEach(0..<stepCount, id: \.self) { i in
                        footprint(index: i, time: t)
                    }
                }
                .frame(height: 36)

                HStack(spacing: 0) {
                    ForEach(Array(title.enumerated()), id: \.offset) { i, char in
                        letter(char, index: i, time: t)
                    }
                }
            }
        }
        .onAppear {
            startDate = Date()
            isRunning = true
        }
        .onDisappear {
            isRunning = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("Loading"))
    }

    // MARK: - Буквы

    private func letter(_ char: Character, index i: Int, time t: Double) -> some View {
        let jump = reduceMotion ? 0 : letterJump(index: i, time: t)

        return Text(String(char))
            .font(.system(size: fontSize, weight: .black, design: .rounded))
            .foregroundStyle(textColor)
            .shadow(color: tint, radius: 0, x: 2, y: 2)
            .scaleEffect(1 + 0.08 * jump, anchor: .bottom)
            .offset(y: -jump * fontSize * 0.45)
    }

    /// 0…1: быстрый прыжок, затем пауза. Сдвиг фазы по индексу даёт волну слева направо.
    private func letterJump(index i: Int, time t: Double) -> CGFloat {
        let raw = t / letterPeriod - Double(i) * letterDelay
        let u = raw - raw.rounded(.down)
        let airShare = 0.32
        guard u < airShare else { return 0 }
        return CGFloat(sin(u / airShare * .pi))
    }

    // MARK: - Следы

    private func footprint(index i: Int, time t: Double) -> some View {
        let stepGap = stepPeriod / Double(stepCount)
        let raw = t / stepPeriod - Double(i) / Double(stepCount)
        let u = raw - raw.rounded(.down)                         // 0…1, возраст следа
        let started = t >= Double(i) * stepGap                   // при старте следы появляются по очереди
        let opacity = started ? max(0, 1 - u * 1.5) : 0          // след «остывает»
        let pop: CGFloat = (started && !reduceMotion) ? CGFloat(max(0, 1 - u * 8)) : 0
        let isLeft = i.isMultiple(of: 2)

        return FootprintShape()
            .fill(tint)
            .frame(width: 24, height: 11)
            .rotationEffect(.degrees(isLeft ? -6 : 6))
            .scaleEffect(1 + 0.35 * pop)
            .opacity(opacity)
            .offset(y: isLeft ? -6 : 6)
    }
}

/// След подошвы, носок смотрит вправо: пятка слева, подошва справа.
private struct FootprintShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.addEllipse(in: CGRect(x: rect.minX,
                                y: rect.minY + h * 0.12,
                                width: w * 0.34,
                                height: h * 0.76))
        p.addEllipse(in: CGRect(x: rect.minX + w * 0.42,
                                y: rect.minY,
                                width: w * 0.58,
                                height: h))
        return p
    }
}
