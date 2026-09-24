import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach
    @EnvironmentObject private var store: Store
    /// Framed closer than usual: the hero has no mat, and arms overhead still fit.
    @StateObject private var avatar: AvatarController = {
        let coach = AvatarController(exerciseID: "idle")
        coach.setCamera(distance: 3.0, height: 0.9)
        return coach
    }()
    @State private var session: SessionItems?
    /// The session zooms out of the card that started it.
    @Namespace private var sessionZoom
    @State private var showingTest = false
    @AppStorage("pelvicFloor") private var pelvicFloor = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    hero

                    if let result = model.latestResult, Retest.isDue(lastCheck: result.date) {
                        retestCard(result)
                    }

                    weekStrip

                    HabitCard()

                    TrainingPlanCard()
                    ChallengeCard()
                    planCard
                    if store.hasPlus {
                        pelvicFloorCard
                    } else {
                        PlusLockedCard(feature: .pelvicFloor)
                    }
                }
                .padding()
            }
            .background(AppBackground())
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { FamilySwitcherButton() }
            }
            .fullScreenCover(item: $session) { wrapper in
                SessionView(items: wrapper.items, voice: voice)
                    .environmentObject(model)
                    .navigationTransition(.zoom(sourceID: wrapper.source, in: sessionZoom))
            }
            .fullScreenCover(isPresented: $showingTest) {
                FloorAgeTestView()
                    .environmentObject(model)
                    .environmentObject(voice)
            }
        }
    }

    private var plan: [PlanItem] {
        guard let profile = model.profile else { return [] }
        return PlanBuilder.today(profile: profile, latest: model.latestResult, pelvicFloor: pelvicFloor && store.hasPlus,
                                 levels: model.levels())
    }

    private var greeting: String {
        let name = model.profile?.name ?? ""
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? String(localized: "Good morning") : hour < 17 ? String(localized: "Good afternoon") : String(localized: "Good evening")
        return name.isEmpty ? part : String(localized: "\(part), \(name)")
    }

    private var weekStrip: some View {
        let days = model.lastSevenDays
        let count = days.filter { $0 }.count
        return VStack(alignment: .leading, spacing: Space.s) {
            Text(count == 0 ? "Let's start your week" : "\(count) of the last 7 days")
                .font(.display(.headline))
            HStack(spacing: Space.s) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, done in
                    Circle()
                        .fill(done ? AnyShapeStyle(Feature.floorAge.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)))
                        .frame(width: 30, height: 30)
                        .shadow(color: done ? Feature.floorAge.tint.opacity(0.4) : .clear, radius: 4, y: 2)
                        .overlay {
                            if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                        }
                }
            }
            Text("Missed a day? No problem. Consistency beats perfection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedCard(.floorAge)
    }

    /// The coach idling beside your Floor Age (or the invitation to find it): the first thing
    /// you see each day. Tapping an exercise in today's session makes this coach demonstrate it.
    /// At accessibility text sizes the greeting and the details take the full width, above and
    /// below the coach and gauge, so nothing overlaps.
    private var hero: some View {
        let large = typeSize.isAccessibilitySize
        let result = model.latestResult
        return VStack(alignment: .leading, spacing: Space.m) {
            if large { Text(greeting).font(.display(.headline)) }
            HStack(alignment: .bottom, spacing: Space.xs) {
                AvatarView(controller: avatar, interactive: false, showsMat: false)
                    .frame(width: large ? 96 : 128, height: large ? 180 : 228)
                    // A soft spotlight lifts the coach off the gradient (the cartoon coach wears orange).
                    .background {
                        RadialGradient(colors: [.white.opacity(0.4), .white.opacity(0)], center: .center, startRadius: 10, endRadius: 120)
                            .frame(width: 260, height: 300)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.m) {
                    if !large { Text(greeting).font(.display(.headline)) }
                    if let result {
                        floorAgeGauge(result)
                    } else {
                        Text("Find your Floor Age").font(.display(.title2))
                    }
                    if !large { heroDetails(result) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Space.xs)
            }
            if large { heroDetails(result) }
        }
        .heroCard(.floorAge)
    }

    /// Fuller the younger your body moves, across the 20 to 90 range of the test norms.
    private func floorAgeGauge(_ result: FloorAgeResult) -> some View {
        ArcGauge(progress: Double(90 - result.floorAge) / 70, lineWidth: 12) {
            VStack(spacing: 0) {
                Text(result.floorAge, format: .number).font(.metric(44))
                Text("Floor Age").font(.caption.weight(.semibold)).opacity(0.9)
            }
        }
        .frame(maxWidth: 190)
        .accessibilityElement(children: .combine)
    }

    /// How the Floor Age compares and the area to focus on, or what the check is and a way in.
    @ViewBuilder
    private func heroDetails(_ result: FloorAgeResult?) -> some View {
        if let result {
            let difference = result.floorAge - result.age
            VStack(alignment: .leading, spacing: Space.s) {
                Text(difference > 0 ? "\(difference) years older than my age (\(result.age))"
                     : difference < 0 ? "\(-difference) years younger than my age (\(result.age))"
                     : "Right on my age (\(result.age))")
                    .font(.footnote.weight(.semibold))
                    .opacity(0.92)
                if let weakest = result.weakest {
                    Label(weakest.area, systemImage: weakest.symbol)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.xs)
                        .background(.white.opacity(0.2), in: Capsule())
                        .accessibilityLabel(String(localized: "Focus: \(weakest.area)"))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("4 quick tests show how old your body moves. Your plan adapts to the result.")
                    .font(.subheadline)
                    .opacity(0.92)
                Button("Start the check") { showingTest = true }
                    .buttonStyle(OnHeroButtonStyle(feature: .floorAge))
            }
        }
    }

    /// Four weeks after the last check: time to see what the training has done.
    private func retestCard(_ result: FloorAgeResult) -> some View {
        Button { showingTest = true } label: {
            HStack(spacing: Space.l) {
                FeatureBadge(feature: .floorAge, symbol: "arrow.triangle.2.circlepath", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time to retest").font(.display(.headline))
                    Text("It's been 4 weeks since your last check. See how far you've come.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .tintedCard(.floorAge)
        }
        .buttonStyle(.plain)
    }

    private var planCard: some View {
        let plan = self.plan
        let minutes = Int((plan.reduce(0) { $0 + $1.estimatedSeconds } / 60).rounded())
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("Today's session").font(.display(.title2))
                Spacer()
                Text("~\(max(minutes, 1)) min").foregroundStyle(.secondary)
            }
            ForEach(plan) { item in
                HStack {
                    Text(item.exercise.name)
                    Spacer()
                    Text(item.amountLabel).foregroundStyle(.secondary)
                    DemoVideoButton(exercise: item.exercise, compact: true) { voice.stop() }
                }
                .contentShape(Rectangle())
                .onTapGesture { avatar.play(item.exercise) }
            }
            Text(plan.contains { DemoVideo.url(for: $0.exercise.id) != nil }
                 ? "Tap an exercise to see the coach demonstrate it, or \(Image(systemName: "play.rectangle.fill")) for a video."
                 : "Tap an exercise to see the coach demonstrate it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                session = SessionItems(items: plan)
            } label: {
                Label(model.didSessionToday ? "Do it again" : "Start with coach", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .tintedCard(.glance)
        .matchedTransitionSource(id: "plan", in: sessionZoom)
    }
}

extension TodayView {
    /// One tap into a guided pelvic floor (Kegel) session, for any time of day.
    fileprivate var pelvicFloorCard: some View {
        Button {
            session = SessionItems(items: PlanBuilder.pelvicFloor, source: "pelvic")
        } label: {
            HStack(spacing: Space.l) {
                FeatureBadge(feature: .plan, symbol: "figure.mind.and.body", size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pelvic floor").font(.display(.headline))
                    Text("12 guided Kegel squeezes · about 2 min. Do them sitting, anywhere.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
            }
            .tintedCard(.plan)
            .matchedTransitionSource(id: "pelvic", in: sessionZoom)
        }
        .buttonStyle(.plain)
    }
}

/// Identifiable wrapper so a plan can drive `fullScreenCover(item:)`.
private struct SessionItems: Identifiable {
    let id = UUID()
    let items: [PlanItem]
    /// Which card it opened from, for the zoom.
    var source = "plan"
}

/// Today's small habit from the LiFE programme: balance or strength folded into an everyday task,
/// drawn from the plan's focus area. One tap ticks it off and it counts towards the week.
struct HabitCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let habit = DailyHabit.today(area: model.planEmphasis?.area)
        let done = model.isHabitDone()
        Button {
            model.setHabit(done: !done)
        } label: {
            HStack(spacing: Space.l) {
                FeatureBadge(feature: .bmi, symbol: habit.symbol, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("Daily habit", feature: .bmi)
                    Text(habit.text)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(done ? "Done for today. It counts towards your week." : "Tap when you've done it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? AnyShapeStyle(Feature.bmi.ink) : AnyShapeStyle(Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .tintedCard(.bmi)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: done) { _, new in new }
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}
