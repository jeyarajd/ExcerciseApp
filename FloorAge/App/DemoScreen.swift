import RealityKit
import SwiftUI

/// Launch with `-demoScreen <name>` to open one screen filled with sample data, for screenshots
/// (CI and the README). Debug builds only; the sample data lives in a temporary file and never
/// touches the person's real data. Add `-voiceEnabled NO` to keep the coach quiet, and
/// `-demoSnapshot <path.png>` to have the app save a picture of itself and quit (no screen
/// recording permission needed).
enum DemoScreen: String, CaseIterable {
    case onboarding, onboardingCoach, today, track, plan, planIntro, cardio, sleep, steps, food, foodPhoto, bmi, progress, settings, session, sessionRest, sessionDone, kegel, test, sitRise, balance, chairStand, reach, cameraChair, cameraBalance, cameraReach, result, share, plus, family, familyAdd, challenge, badge, drop, widgets, video, portrait

    /// `-demoDark YES` shows the app in dark mode whatever the device is set to (screenshots).
    static var forcesDark: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "demoDark")
        #else
        false
        #endif
    }

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
        // Levels: chair stands felt easy last time; balance at the tandem stance.
        let lastSession = cal.date(byAdding: .day, value: -1, to: Date())!
        let families = ["sit_to_stand", "balance"]
        model.logSession([FamilyResult(family: "sit_to_stand", level: 1, target: 10, done: 10),
                          FamilyResult(family: "balance", level: 1, target: 30, done: 30)], on: lastSession)
        model.rateSession(.easy, families: families, on: lastSession)
        model.setHabit(done: true, on: lastSession)
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
        // Twelve days into the 30-day challenge.
        model.startChallenge(on: cal.date(byAdding: .day, value: -11, to: Date())!)
        for daysAgo in [3, 6, 8, 9, 10, 11] {
            model.setPlanDay(cal.date(byAdding: .day, value: -daysAgo, to: Date())!, done: true)
        }
        model.newBadge = nil

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
            DemoScreen.prepareForSnapshot()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .onboarding:
            OnboardingView()
        case .onboardingCoach:
            OnboardingView(startPage: 2)
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
            SessionView(items: PlanBuilder.today(profile: model.profile!, latest: model.latestResult, levels: model.levels()), voice: voice)
        case .sessionRest:
            SessionView(items: PlanBuilder.today(profile: model.profile!, latest: model.latestResult, levels: model.levels()), voice: voice, demoPhase: .rest)
        case .sessionDone:
            SessionView(items: PlanBuilder.today(profile: model.profile!, latest: model.latestResult, levels: model.levels()), voice: voice, demoPhase: .done)
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
        case .challenge:
            NavigationStack { ChallengeView() }
        case .badge:
            MainTabs(initial: .today).overlay { BadgeCelebration(badge: .seven) {} }
        case .drop:
            NavigationStack {
                FloorAgeResultView(result: model.latestResult!, history: Array(model.results.dropLast()))
                    .navigationTitle("Your Floor Age")
            }
        case .widgets:
            WidgetGallery()
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

}

/// Renders the app's own window to a PNG, then quits. RealityKit draws with Metal, which a normal
/// view capture misses, so each 3D view's own snapshot is laid over it first.
@MainActor
private enum SelfSnapshot {
    static func save(to path: String) {
        capture { image in
            let ok = (try? image?.pngData()?.write(to: URL(fileURLWithPath: path))) != nil
            exit(ok ? 0 : 1)
        }
    }

    /// The window as a picture, with each 3D view's own render laid over it.
    static func capture(_ done: @escaping (UIImage?) -> Void) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return done(nil) }
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
            done(image)
        }
    }

    private static func allSubviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }
}

/// `-demoAudit <folder>`: plays every exercise and saves a picture of the coach at each keyframe
/// and halfway between keyframes (mirrored too, for exercises that switch sides), then quits.
/// Launch it once per coach with `-coachLook female|male` and `-coachStyle realistic|friendly`.
struct AvatarAuditView: View {
    let folder: String
    @StateObject private var avatar = AvatarController()

    static var folder: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "demoAudit")
        #else
        nil
        #endif
    }

    var body: some View {
        AvatarView(controller: avatar)
            .ignoresSafeArea()
            .background(AppBackground())
            .overlay(alignment: .top) {
                Text(avatar.exercise?.name ?? "")
                    .font(.headline)
                    .padding(Space.s)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 60)
            }
            .task { await run() }
    }

    @MainActor
    private func run() async {
        try? await Task.sleep(for: .seconds(2))
        // `-demoAuditExercises squat,toe_reach` limits it to those.
        let only = UserDefaults.standard.string(forKey: "demoAuditExercises").map { Set($0.split(separator: ",").map(String.init)) }
        for exercise in ExerciseLibrary.shared.exercises where only?.contains(exercise.id) ?? true {
            let times = exercise.keyframes.map(\.t)
            let moments = zip(times, times.dropFirst()).flatMap { [$0, ($0 + $1) / 2] } + [times.last ?? 0]
            for mirrored in exercise.mirrorHalfway == true ? [false, true] : [false] {
                avatar.play(exercise, mirrored: mirrored)
                avatar.speed = 0
                // `-demoAuditYaw 200` looks from that side instead of the exercise's own angle.
                if UserDefaults.standard.object(forKey: "demoAuditYaw") != nil {
                    avatar.turn(toDegrees: UserDefaults.standard.double(forKey: "demoAuditYaw"))
                }
                for t in moments {
                    avatar.seek(to: t)
                    // Long enough for the camera to turn and the framing to settle.
                    try? await Task.sleep(for: .seconds(1.3))
                    let name = String(format: "%@%@-%05.2f.png", exercise.id, mirrored ? "-mirrored" : "", t)
                    let image = await withCheckedContinuation { done in SelfSnapshot.capture { done.resume(returning: $0) } }
                    try? image?.pngData()?.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
                }
            }
        }
        exit(0)
    }
}

/// Close-up of the coach's face and hair, for reviewing the avatar.
private struct PortraitView: View {
    @StateObject private var avatar = AvatarController(exerciseID: "idle")

    var body: some View {
        AvatarView(controller: avatar)
            .ignoresSafeArea()
            .onAppear { avatar.setCamera(distance: 1.05, height: 1.6, fitsWholeBody: false) }
    }
}

/// The Home Screen and Lock Screen widgets drawn in the app, for screenshots (widgets themselves
/// can't be captured on a Mac).
private struct WidgetGallery: View {
    private let snapshot = FloorAgeSnapshot.sample

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("Home Screen").font(.display(.headline)).foregroundStyle(.white)
                HStack(spacing: Space.l) {
                    tile(FloorAgeWidgetView(snapshot: snapshot, familyOverride: .systemSmall), background: Feature.floorAge.gradient)
                    tile(StepsWidgetView(snapshot: snapshot, familyOverride: .systemSmall), background: Feature.steps.gradient)
                }
                tile(FloorAgeWidgetView(snapshot: snapshot, familyOverride: .systemMedium), background: Feature.floorAge.gradient, wide: true)
                Text("Lock Screen").font(.display(.headline)).foregroundStyle(.white).padding(.top, Space.s)
                VStack(spacing: Space.l) {
                    FloorAgeWidgetView(snapshot: snapshot, familyOverride: .accessoryInline)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: Space.l) {
                        FloorAgeWidgetView(snapshot: snapshot, familyOverride: .accessoryCircular)
                            .frame(width: 64, height: 64)
                        StepsWidgetView(snapshot: snapshot, familyOverride: .accessoryCircular)
                            .frame(width: 64, height: 64)
                        FloorAgeWidgetView(snapshot: snapshot, familyOverride: .accessoryRectangular)
                            .font(.caption)
                            .frame(width: 160, alignment: .leading)
                    }
                }
                .foregroundStyle(.white)
                .padding(Space.l)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            }
            .padding(Space.xl)
        }
        .background(LinearGradient(colors: [Color(red: 0.12, green: 0.2, blue: 0.4), Color(red: 0.45, green: 0.25, blue: 0.55)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func tile<V: View>(_ view: V, background: LinearGradient, wide: Bool = false) -> some View {
        view
            .padding(Space.l)
            .frame(width: wide ? 346 : 165, height: 165)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }
}

extension DemoScreen {
    /// Sizes the Mac window like a phone and, with `-demoSnapshot`, saves a picture after 6 s.
    static func prepareForSnapshot() {
        phoneSizedWindow()
        if let path = UserDefaults.standard.string(forKey: "demoSnapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { SelfSnapshot.save(to: path) }
        }
    }

    /// On a Mac (Catalyst), size the window like an iPhone so screenshots match the phone layout.
    private static func phoneSizedWindow() {
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
