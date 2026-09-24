import RealityKit
import SwiftUI

/// Launch with `-demoScreen <name>` to open one screen filled with sample data, for screenshots
/// (CI and the README). Debug builds only; the sample data lives in a temporary file and never
/// touches the person's real data. Add `-voiceEnabled NO` to keep the coach quiet, and
/// `-demoSnapshot <path.png>` to have the app save a picture of itself and quit (no screen
/// recording permission needed).
enum DemoScreen: String, CaseIterable {
    case onboarding, today, track, steps, food, foodPhoto, bmi, progress, settings, session, kegel, test, balance, result, video, portrait

    static var current: DemoScreen? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "demoScreen").flatMap(DemoScreen.init(rawValue:))
        #else
        nil
        #endif
    }

    /// A 52-year-old with a knee limitation, three checks over two months and four recent sessions.
    static func sampleModel() -> AppModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("floorage-demo.json")
        try? FileManager.default.removeItem(at: url)
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
        case .balance:
            FloorAgeTestView(startStep: 2)
        case .result:
            NavigationStack {
                FloorAgeResultView(result: model.latestResult!)
                    .navigationTitle("Your Floor Age")
            }
        case .portrait:
            PortraitView()
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
