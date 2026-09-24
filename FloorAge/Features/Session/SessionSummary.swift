import SwiftUI

/// The Floor Age area an exercise trains, from its `focus` tags in exercises.json. Gives the
/// session its colours (the progress ring, "Next up") and the summary its "areas you worked".
enum TrainingArea: String, CaseIterable, Identifiable {
    case legs, floor, balance, flexibility, pelvicFloor

    var id: Self { self }

    /// Warm-ups ("warmup") have no area.
    init?(focus: String) {
        switch focus {
        case "legs": self = .legs
        case "floor": self = .floor
        case "balance": self = .balance
        case "flex": self = .flexibility
        case "pelvic floor": self = .pelvicFloor
        default: return nil
        }
    }

    /// The Floor Age check that measures it; pelvic floor has none.
    var test: FloorTest? {
        switch self {
        case .legs: .chairStand
        case .floor: .sitRise
        case .balance: .balance
        case .flexibility: .reach
        case .pelvicFloor: nil
        }
    }

    var name: String { test?.area ?? String(localized: "Pelvic floor") }
    var feature: Feature { test?.feature ?? .plan }
    var symbol: String { test?.symbol ?? "figure.mind.and.body" }
}

extension Exercise {
    var areas: [TrainingArea] { focus.compactMap(TrainingArea.init(focus:)) }
    /// The colours of the main area it trains; warm-ups get the walking orange.
    var feature: Feature { areas.first?.feature ?? .steps }
}

/// An exercise's key position in the mannequin style of the camera outline. Drawn once per
/// exercise and kept for the rest of the app's run.
struct PoseThumbnailView: View {
    let exercise: Exercise
    var side: CGFloat = 72

    var body: some View {
        Group {
            if let image = Self.image(for: exercise, side: side) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: exercise.feature.symbol).font(.title).foregroundStyle(exercise.feature.gradient)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    @MainActor private static var cache: [String: UIImage] = [:]

    @MainActor
    static func image(for exercise: Exercise, side: CGFloat) -> UIImage? {
        let key = "\(exercise.id)-\(Int(side))"
        if let image = cache[key] { return image }
        // Drawn on a large canvas (the mannequin has a minimum size) and scaled down to 3× pixels.
        let canvas: CGFloat = 240
        guard let rough = Mannequin(joints: PoseThumbnail.joints(for: exercise, size: CGSize(width: canvas, height: canvas)))
        else { return nil }
        // Fit the drawn body (head, hands and feet included) with room for its glow.
        let box = rough.bounds, inset = canvas * 0.08
        let scale = min((canvas - 2 * inset) / box.width, (canvas - 2 * inset) / box.height)
        let fitted = rough.joints.mapValues { p in
            CGPoint(x: (p.x - box.midX) * scale + canvas / 2, y: (p.y - box.midY) * scale + canvas / 2)
        }
        guard let figure = Mannequin(joints: fitted) else { return nil }
        let feature = exercise.feature
        let renderer = ImageRenderer(content: Canvas { context, _ in figure.draw(in: &context, feature: feature) }
            .frame(width: canvas, height: canvas))
        renderer.scale = 3 * side / canvas
        let image = renderer.uiImage
        cache[key] = image
        return image
    }
}

/// During rest: what's coming, how it looks, and a way to start it now.
struct NextUpCard: View {
    let item: PlanItem
    let onSkip: () -> Void

    var body: some View {
        let feature = item.exercise.feature
        VStack(spacing: Space.l) {
            HStack(spacing: Space.l) {
                PoseThumbnailView(exercise: item.exercise)
                    .padding(Space.xs)
                    .background(feature.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                VStack(alignment: .leading, spacing: Space.xs) {
                    Eyebrow("Next up", feature: feature)
                    Text(item.exercise.name).font(.display(.title3)).fixedSize(horizontal: false, vertical: true)
                    Text(item.amountLabel).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            Button(action: onSkip) {
                Text("Skip rest")
            }
            .buttonStyle(GradientButtonStyle(feature: feature))
        }
        .tintedCard(feature)
    }
}

/// The end of a session: time, reps, the areas worked and the streak, with a card to share.
struct SessionSummaryView: View {
    let minutes: Int
    let reps: Int
    let practised: [PlanItem]
    let streak: Int
    let onFinish: () -> Void
    @State private var shareImage: UIImage?
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var areas: [TrainingArea] {
        var seen: [TrainingArea] = []
        for area in practised.flatMap(\.exercise.areas) where !seen.contains(area) { seen.append(area) }
        return seen
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                VStack(spacing: Space.s) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 52))
                        .symbolEffect(.bounce, value: shown && !reduceMotion)
                        .accessibilityHidden(true)
                    Text("Session complete").font(.display(.largeTitle))
                    Text("You moved today. That's what counts.")
                        .font(.headline)
                        .opacity(0.92)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .heroCard(.calories, symbol: "checkmark.seal.fill", padding: Space.xl)

                // Side by side, or one under another at accessibility text sizes.
                let stats = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Space.m)) : AnyLayout(HStackLayout(spacing: Space.m))
                stats {
                    stat(minutes, "min", symbol: "clock.fill", feature: .plan)
                    stat(reps, "reps", symbol: "repeat", feature: .calories)
                    stat(practised.count, "exercises", symbol: "figure.strengthtraining.functional", feature: .bmi)
                }

                if !areas.isEmpty {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Eyebrow("Areas you worked", feature: .plan)
                        ForEach(areas) { area in
                            HStack(spacing: Space.m) {
                                FeatureBadge(feature: area.feature, symbol: area.symbol, size: 36)
                                Text(area.name).font(.body.weight(.semibold))
                                Spacer()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tintedCard(.plan)
                }

                streakCard

                VStack(spacing: Space.m) {
                    Button(action: onFinish) {
                        Text("Finish")
                    }
                    .buttonStyle(GradientButtonStyle(feature: .calories))
                    if let shareImage {
                        ShareLink(item: Image(uiImage: shareImage),
                                  message: Text(shareMessage),
                                  preview: SharePreview("My Floor Age session", image: Image(uiImage: shareImage))) {
                            Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Feature.floorAge.colors[1])
                    }
                }
                .padding(.top, Space.xs)
            }
            .padding()
        }
        .background(AppBackground())
        .onAppear {
            shown = true
            shareImage = SessionShareCard(minutes: minutes, reps: reps, exercises: practised.count, streak: streak, areas: areas)
                .renderShareCard()
        }
    }

    private var streakCard: some View {
        HStack(spacing: Space.l) {
            Image(systemName: "flame.fill")
                .font(.system(size: 30))
                .foregroundStyle(Feature.steps.gradient)
                .symbolEffect(.bounce, value: shown && !reduceMotion)
                .frame(width: 56, height: 56)
                .background(Feature.steps.tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(streak >= 2 ? "\(streak) days in a row" : "Day one").font(.display(.title3))
                Text(streak >= 2 ? "Missing a day never undoes your progress." : "Come back tomorrow to start a streak.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .tintedCard(.steps)
    }

    private func stat(_ value: Int, _ unit: LocalizedStringKey, symbol: String, feature: Feature) -> some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol).font(.headline).foregroundStyle(feature.gradient)
            Text(value, format: .number).font(.metric(30)).lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .tintedCard(feature, padding: Space.m)
        .accessibilityElement(children: .combine)
    }

    private var shareMessage: String {
        let text = String(localized: "I just finished a \(minutes)-minute Floor Age session. Can you get up off the floor without using your hands? Find your Floor Age:")
        return text + " " + AppLinks.findTheApp
    }
}

/// The story-sized share picture for a finished session: the streak (or minutes) as the big
/// number, then time, reps and the areas worked. Never the person's name.
struct SessionShareCard: View {
    let minutes: Int
    let reps: Int
    let exercises: Int
    let streak: Int
    let areas: [TrainingArea]

    var body: some View {
        ShareCardFrame {
            Text("I moved today")
                .font(.system(size: 13, weight: .heavy))
                .tracking(3)
                .textCase(.uppercase)
                .opacity(0.9)
            Text("\(streak >= 2 ? streak : minutes)")
                .font(.system(size: 150, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            Label(streak >= 2 ? "days in a row" : "minutes of movement",
                  systemImage: streak >= 2 ? "flame.fill" : "clock.fill")
                .font(.system(size: 17, weight: .bold, design: .serif))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.white.opacity(0.2), in: Capsule())

            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    figure(minutes, "min")
                    figure(reps, "reps")
                    figure(exercises, "exercises")
                }
                if !areas.isEmpty {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            ForEach(areas) { area in
                                Image(systemName: area.symbol)
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 26, height: 26)
                                    .background(area.feature.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                        // Names fit for up to three areas; beyond that the icons say it.
                        Text(areas.count <= 3 ? areas.map(\.name).formatted(.list(type: .and))
                                              : String(localized: "\(areas.count) areas worked"))
                            .font(.system(size: 13, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 20)
        }
    }

    private func figure(_ value: Int, _ unit: LocalizedStringKey) -> some View {
        VStack(spacing: 0) {
            Text(value, format: .number).font(.system(size: 26, weight: .heavy, design: .rounded))
            Text(unit).font(.system(size: 12, weight: .semibold)).opacity(0.85)
        }
        .frame(maxWidth: .infinity)
    }
}
