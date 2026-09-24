import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach
    @StateObject private var avatar = AvatarController(exerciseID: "idle")
    @State private var session: SessionItems?
    @State private var showingTest = false
    @AppStorage("pelvicFloor") private var pelvicFloor = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AvatarView(controller: avatar)
                        .frame(height: 300)
                        .overlay(alignment: .bottomLeading) {
                            Text(greeting)
                                .font(.headline)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(12)
                        }

                    weekStrip

                    if model.latestResult == nil {
                        testPrompt
                    } else if let result = model.latestResult {
                        floorAgeSummary(result)
                    }

                    TrainingPlanCard()
                    planCard
                    pelvicFloorCard
                }
                .padding()
            }
            .background(AppBackground())
            .navigationTitle("Today")
            .fullScreenCover(item: $session) { wrapper in
                SessionView(items: wrapper.items, voice: voice)
                    .environmentObject(model)
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
        return PlanBuilder.today(profile: profile, latest: model.latestResult, pelvicFloor: pelvicFloor)
    }

    private var greeting: String {
        let name = model.profile?.name ?? ""
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var weekStrip: some View {
        let days = model.lastSevenDays
        let count = days.filter { $0 }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text(count == 0 ? "Let's start your week" : "\(count) of the last 7 days")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, done in
                    Circle()
                        .fill(done ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(width: 28, height: 28)
                        .overlay {
                            if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                        }
                }
            }
            Text("Missed a day? No problem. Consistency beats perfection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var testPrompt: some View {
        Button {
            showingTest = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.cross.training")
                    .font(.largeTitle)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find your Floor Age").font(.headline)
                    Text("4 quick tests show how old your body moves. Your plan adapts to the result.")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .foregroundStyle(.white)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func floorAgeSummary(_ result: FloorAgeResult) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Floor Age").font(.subheadline).foregroundStyle(.secondary)
                Text("\(result.floorAge)").font(.system(size: 40, weight: .bold, design: .rounded))
            }
            Spacer()
            if let weakest = result.weakest {
                VStack(alignment: .trailing) {
                    Text("Focus").font(.subheadline).foregroundStyle(.secondary)
                    Text(weakest.area).font(.headline)
                }
            }
        }
        .card()
    }

    private var planCard: some View {
        let plan = self.plan
        let minutes = Int((plan.reduce(0) { $0 + $1.estimatedSeconds } / 60).rounded())
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's session").font(.title2.bold())
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
        .card()
    }
}

extension TodayView {
    /// One tap into a guided pelvic floor (Kegel) session, for any time of day.
    fileprivate var pelvicFloorCard: some View {
        Button {
            session = SessionItems(items: PlanBuilder.pelvicFloor)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "figure.mind.and.body")
                    .font(.title)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pelvic floor").font(.headline)
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
            .card()
        }
        .buttonStyle(.plain)
    }
}

/// Identifiable wrapper so a plan can drive `fullScreenCover(item:)`.
private struct SessionItems: Identifiable {
    let id = UUID()
    let items: [PlanItem]
}
