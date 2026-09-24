import SwiftUI

@main
struct FloorAgeApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var voice = VoiceCoach()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(voice)
                .tint(Color("AccentColor"))
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    /// Launch with `-demoExercise <id>` to open straight into one exercise (used for CI screenshots).
    private let demoExercise = UserDefaults.standard.string(forKey: "demoExercise")

    var body: some View {
        if let demoExercise {
            DemoView(exerciseID: demoExercise)
        } else if model.profile == nil {
            OnboardingView()
        } else {
            MainTabs()
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
            CoachChatView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right.fill") }
            HistoryView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
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
