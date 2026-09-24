import SwiftUI

@main
struct FloorAgeApp: App {
    @StateObject private var model = DemoScreen.current == nil ? AppModel() : DemoScreen.sampleModel()
    @StateObject private var voice = VoiceCoach()
    @StateObject private var steps = DemoScreen.current == nil ? StepCounter() : StepCounter.sample()
    @StateObject private var store = DemoScreen.current == nil ? Store() : Store(preview: DemoScreen.hasPlus)
    @StateObject private var snapshots = SnapshotPublisher()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Appearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(voice)
                .environmentObject(steps)
                .environmentObject(store)
                .tint(Color("AccentColor"))
                .onAppear {
                    guard DemoScreen.current == nil else { return }
                    snapshots.attach(model: model, steps: steps)
                    WatchLink.shared.activate()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refreshReminders() }
            Task { await store.refreshEntitlement() }
            if model.profile != nil { steps.start() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: Store

    /// Launch with `-demoExercise <id>` to open straight into one exercise (used for CI screenshots).
    private let demoExercise = UserDefaults.standard.string(forKey: "demoExercise")

    var body: some View {
        if let demoExercise {
            DemoView(exerciseID: demoExercise)
        } else if let screen = DemoScreen.current {
            DemoScreen.view(for: screen)
        } else if model.profile == nil {
            OnboardingView()
        } else {
            MainTabs()
                .overlay {
                    if let badge = model.newBadge {
                        BadgeCelebration(badge: badge) { withAnimation { model.newBadge = nil } }
                            .transition(.opacity)
                    }
                }
                .onAppear(perform: keepFamilyInPlus)
                .onChange(of: store.hasPlus) { keepFamilyInPlus() }
        }
    }

    /// Family members are part of Plus; without it the app opens as the owner.
    private func keepFamilyInPlus() {
        if !store.hasPlus, !model.isOwner { model.switchMember(model.owner.id) }
    }
}

struct MainTabs: View {
    enum Tab { case today, track, progress, settings }
    @State private var tab: Tab

    init(initial: Tab = .today) {
        _tab = State(initialValue: initial)
    }

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(Tab.today)
            TrackView()
                .tabItem { Label("Track", systemImage: "heart.text.square.fill") }
                .tag(Tab.track)
            HistoryView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        // Links from the widgets.
        .onOpenURL { url in
            tab = url.host == "steps" ? .track : .today
        }
    }
}

/// Full-screen coach playing one exercise, optionally frozen at `-demoTime <seconds>`.
struct DemoView: View {
    @StateObject private var avatar: AvatarController

    init(exerciseID: String) {
        let controller = AvatarController(exerciseID: exerciseID)
        if UserDefaults.standard.object(forKey: "demoTime") != nil {
            controller.speed = 0
            controller.seek(to: UserDefaults.standard.double(forKey: "demoTime"))
        }
        _avatar = StateObject(wrappedValue: controller)
    }

    var body: some View {
        AvatarView(controller: avatar)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                Text(avatar.exercise?.name ?? "")
                    .font(.title2.bold())
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 60)
            }
    }
}
