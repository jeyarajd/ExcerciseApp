import RealityKit
import SwiftUI

/// Launch with `-demoScreen <name>` to open one screen filled with sample data, for screenshots
/// (CI and the README). Debug builds only; the sample data lives in a temporary file and never
/// touches the person's real data. Add `-voiceEnabled NO` to keep the coach quiet, and
/// `-demoSnapshot <path.png>` to have the app save a picture of itself and quit (no screen
/// recording permission needed).
enum DemoScreen: String, CaseIterable {
    case onboarding, today, track, plan, planIntro, cardio, sleep, steps, food, foodPhoto, bmi, progress, settings, session, kegel, test, sitRise, balance, chairStand, reach, cameraChair, cameraBalance, cameraReach, result, share, plus, family, familyAdd, video, portrait

    /// Screens show Floor Age Plus unlocked unless launched with `-demoPlus NO`.
    static var hasPlus: Bool {
        UserDefaults.standard.object(forKey: "demoPlus") == nil || UserDefaults.standard.bool(forKey: "demoPlus")
    }

    static var current: DemoScreen? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "demoScreen").flatMap(DemoScreen.init(rawValue:))
        #else
        nil
        #endif
    }

    /// A 52-year-old with a knee limitation, three checks over two months and four recent sessions.
    static func sampleModel() -> AppModel {
        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent("floorage-demo.json")
        // Start clean, including family members from an earlier run.
        for file in (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? [] where file.hasPrefix("floorage-demo") {
            try? FileManager.default.removeItem(at: tmp.appendingPathComponent(file))
        }
        let model = AppModel(fileURL: url)
        model.profile = Profile(name: "Priya", age: 52, limitations: [.knee], gender: .female)
        let cal = Calendar.current
        let checks: [(weeksAgo: Int, scores: [String: Double])] = [
            (8, ["sitRise": 6, "balance": 18, "chairStand": 13, "reach": 2]),
            (4, ["sitRise": 6.5, "balance": 24, "chairStand": 15, "reach": 2]),
            (0, ["sitRise": 7.5, "balance": 29, "chairStand": 17, "reach": 3]),
        ]
        for check in checks {
            let date = cal.date(byAdding: .weekOfYear, value: -check.weeksAgo, to: Date())!
            model.add(FloorAgeResult(date: date, age: 52, scores: check.scores))
        }
        for daysAgo in [1, 2, 4, 5] {
            model.completeSession(on: cal.date(byAdding: .day, value: -daysAgo, to: Date())!)
        }
        for (weeksAgo, kg) in [(8, 71.5), (4, 70.2), (0, 68.8)] {
            model.updateBody(heightCm: 158, weightKg: kg, on: cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date())!)
        }
        let today = cal.startOfDay(for: Date())
        for (hour, name, kcal, servings) in [(8, "Poha", 250, 1.0), (8, "Chai with sugar", 90, 1.0), (13, "Roti / chapati", 110, 2.0),
                                             (13, "Dal", 150, 1.0), (13, "Mixed veg sabzi", 130, 1.0), (17, "Banana", 105, 1.0)] {
            model.addFood(FoodEntry(date: cal.date(byAdding: .hour, value: hour, to: today)!, name: name, kcal: kcal, servings: servings))
        }
        // Two weeks of nights, mostly a little under 7 hours.
        for (daysAgo, bedHour, bedMinute, hours) in [(13, 23, 10, 6.8), (12, 23, 40, 6.2), (11, 22, 50, 7.3), (10, 23, 30, 6.5),
                                                     (9, 0, 15, 5.9), (8, 23, 0, 7.4), (7, 22, 45, 7.8), (6, 23, 20, 6.9),
                                                     (5, 23, 35, 6.4), (4, 22, 55, 7.2), (3, 23, 45, 6.1), (2, 23, 5, 7.0),
                                                     (1, 22, 40, 7.6), (0, 23, 15, 6.9)] {
            let wakeDay = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            let bedDay = bedHour < 12 ? wakeDay : cal.date(byAdding: .day, value: -1, to: wakeDay)!
            let bed = cal.date(bySettingHour: bedHour, minute: bedMinute, second: 0, of: bedDay)!
            model.logSleep(SleepEntry(bedtime: bed, wake: bed.addingTimeInterval(hours * 3600), quality: hours >= 7 ? 3 : 2))
        }
        // Priya's parents, tested on her phone (family profiles).
        let owner = model.activeMemberID
        for (name, age, gender, scores) in [("Raj", 78, Gender.male, ["sitRise": 4.5, "balance": 7.0, "chairStand": 10.0, "reach": 1.0]),
                                            ("Meena", 74, Gender.female, ["sitRise": 5.5, "balance": 12.0, "chairStand": 12.0, "reach": 3.0])] {
            model.addMember()
            model.profile = Profile(name: name, age: age, limitations: name == "Raj" ? [.knee] : [], gender: gender)
            model.add(FloorAgeResult(age: age, scores: scores))
        }
        model.switchMember(owner)
        return model
    }

    @MainActor @ViewBuilder
    static func view(for screen: DemoScreen) -> some View {
        DemoScreenHost(screen: screen)
    }
}

private struct DemoScreenHost: View {
    let screen: DemoScreen
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach

    var body: some View {
        content.onAppear {
            phoneSizedWindow()
            if let path = UserDefaults.standard.string(forKey: "demoSnapshot") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { SelfSnapshot.save(to: path) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .onboarding:
            OnboardingView()
        case .today:
            MainTabs(initial: .today)
        case .track:
            MainTabs(initial: .track)
        case .plan:
            NavigationStack { PlanView() }
                .onAppear {
                    // Week 2, day 3 of a brisk walking plan, with the first days done.
                    let start = Calendar.current.date(byAdding: .day, value: -9, to: Date())!
                    model.startPlan(.briskWalk, averageSteps: 5200, on: start)
                    for back in [9, 8, 6, 5, 3, 2, 1] {
                        model.setPlanDay(Calendar.current.date(byAdding: .day, value: -back, to: Date())!, done: true)
                    }
                }
        case .sleep:
            NavigationStack { SleepView() }
        case .planIntro:
            NavigationStack { PlanView() }
        case .cardio:
            IntervalWorkoutView(title: "Run/walk, week 1", intervals: TrainingPlan.couchTo5K(week: 1, run: 0))
        case .steps:
            NavigationStack { StepsView() }
        case .food:
            NavigationStack { FoodLogView() }
        case .bmi:
            NavigationStack { BMIView() }
        case .foodPhoto:
            // What the classifier typically returns for a thali with biryani, curry and raita.
            FoodPhotoView(day: Date(), preview: FoodRecognizer.guesses(from: [
                ("food", 0.97), ("biryani", 0.81), ("curry", 0.62), ("yogurt", 0.44), ("salad", 0.2), ("fruit", 0.15),
            ]))
        case .progress:
            MainTabs(initial: .progress)
        case .settings:
            MainTabs(initial: .settings)
        case .session:
            SessionView(items: PlanBuilder.today(profile: model.profile!, latest: model.latestResult), voice: voice)
        case .kegel:
            SessionView(items: PlanBuilder.pelvicFloor, voice: voice)
        case .test:
            FloorAgeTestView()
        case .sitRise:
            FloorAgeTestView(startStep: 1)
        case .balance:
            FloorAgeTestView(startStep: 2)
        case .chairStand:
            FloorAgeTestView(startStep: 3)
        case .reach:
            FloorAgeTestView(startStep: 4)
        case .cameraChair:
            FloorAgeTestView(startStep: 3, demoCamera: .chairStand)
        case .cameraBalance:
            FloorAgeTestView(startStep: 2, demoCamera: .balance)
        case .cameraReach:
            FloorAgeTestView(startStep: 4, demoCamera: .reach)
        case .family:
            FamilyView()
        case .familyAdd:
            OnboardingView().onAppear { if model.isOwner { model.addMember() } }
        case .share:
            ShareCardView(result: model.latestResult!)
        case .result:
            NavigationStack {
                FloorAgeResultView(result: model.latestResult!)
                    .navigationTitle("Your Floor Age")
            }
        case .portrait:
            PortraitView()
        case .plus:
            PlusView(highlight: .plan)
        case .video:
            if let url = DemoVideo.url(for: "squat") {
                DemoVideoSheet(exercise: ExerciseLibrary.shared["squat"], url: url)
            }
        }
    }

    /// On a Mac (Catalyst), size the window like an iPhone so screenshots match the phone layout.
    private func phoneSizedWindow() {
        #if targetEnvironment(macCatalyst)
        // `-demoHeight <points>` makes a taller window to capture a whole scrolling screen.
        let height = UserDefaults.standard.double(forKey: "demoHeight")
        let size = CGSize(width: 402, height: height > 0 ? height : 874)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = size
            scene.sizeRestrictions?.maximumSize = size
        }
        #endif
    }
}

/// Renders the app's own window to a PNG, then quits. RealityKit draws with Metal, which a normal
/// view capture misses, so each 3D view's own snapshot is laid over it first.
@MainActor
private enum SelfSnapshot {
    static func save(to path: String) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { exit(1) }
        let arViews = allSubviews(of: window).compactMap { $0 as? ARView }
        let group = DispatchGroup()
        var stills: [UIImageView] = []
        for view in arViews {
            group.enter()
            view.snapshot(saveToHDR: false) { image in
                if let image {
                    let still = UIImageView(image: image)
                    still.frame = view.bounds
                    view.addSubview(still)
                    stills.append(still)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            stills.forEach { $0.removeFromSuperview() }
            let ok = (try? image.pngData()?.write(to: URL(fileURLWithPath: path))) != nil
            exit(ok ? 0 : 1)
        }
    }

    private static func allSubviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }
}

/// Close-up of the coach's face and hair, for reviewing the avatar.
private struct PortraitView: View {
    @StateObject private var avatar = AvatarController(exerciseID: "idle")

    var body: some View {
        AvatarView(controller: avatar)
            .ignoresSafeArea()
            .onAppear { avatar.setCamera(distance: 1.05, height: 1.6) }
    }
}
