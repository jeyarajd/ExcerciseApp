import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach
    @StateObject private var avatar = AvatarController(exerciseID: "idle")
    @State private var session: SessionItems?
    @State private var showingTest = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AvatarView(controller: avatar)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
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

                    planCard
                }
                .padding()
            }
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
        return PlanBuilder.today(profile: profile, latest: model.latestResult)
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
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
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
                }
                .contentShape(Rectangle())
                .onTapGesture { avatar.play(item.exercise) }
            }
            Text("Tap an exercise to see the coach demonstrate it.")
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
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Identifiable wrapper so a plan can drive `fullScreenCover(item:)`.
private struct SessionItems: Identifiable {
    let id = UUID()
    let items: [PlanItem]
}
