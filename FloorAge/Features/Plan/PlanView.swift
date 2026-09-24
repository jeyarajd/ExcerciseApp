import SwiftUI
import UIKit

/// The weekly training plan: which program suits the person and why, this week's days with sets,
/// reps, walking/running intervals and step goals, and the sources behind the numbers.
struct PlanView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var steps: StepCounter
    @EnvironmentObject private var voice: VoiceCoach
    @State private var choice: TrainingPlan.Program?
    @State private var cardio: CardioWorkout?
    @State private var session: StrengthSession?
    @State private var confirmingRestart = false
    @State private var offeringReminder = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let profile = model.profile {
                    if let program = model.planProgram, let position = model.planPosition() {
                        let week = TrainingPlan.week(position.week, program: program, profile: profile, averageSteps: model.planBaseSteps)
                        weekHeader(week, finished: position.week > program.weeks)
                        ForEach(week.days, id: \.index) { day in
                            dayCard(day, week: week, date: date(ofDay: day.index, week: position.week), isToday: day.index == position.day)
                        }
                        Button("Change or restart plan", role: .destructive) { confirmingRestart = true }
                            .font(.subheadline)
                    } else {
                        intro(profile)
                    }
                    sources
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle("Training plan")
        .onAppear { steps.start() }
        .confirmationDialog("Restart your plan? Your progress in this plan will be cleared.", isPresented: $confirmingRestart, titleVisibility: .visible) {
            Button("Restart", role: .destructive) {
                model.stopPlan()
                Task { await model.refreshReminders() }
            }
        }
        .alert("Remind you in the evening?", isPresented: $offeringReminder) {
            Button("Yes, at \(ReminderTime.label)") {
                Task { if await Reminders.enable() { await model.refreshReminders() } }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("One notification a day, only if you haven't done that day's training yet. You can change the time in Settings.")
        }
        .fullScreenCover(item: $cardio) { workout in
            IntervalWorkoutView(title: workout.title, intervals: workout.intervals) {
                model.setPlanDay(Date(), done: true)
                Task { await model.refreshReminders() }
            }
            .environmentObject(voice)
            .environmentObject(steps)
        }
        .fullScreenCover(item: $session) { session in
            SessionView(items: session.items, voice: voice)
                .environmentObject(model)
        }
    }

    // MARK: - Before starting

    private func intro(_ profile: Profile) -> some View {
        let recommended = TrainingPlan.recommendedProgram(for: profile)
        let selected = choice ?? recommended
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FeatureBadge(feature: .plan)
                Text("Your plan").font(.display(.title2))
            }
            Text(reason(for: recommended, profile: profile))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Plan", selection: Binding(get: { selected }, set: { choice = $0 })) {
                ForEach(TrainingPlan.Program.allCases) { program in
                    Text(program == recommended ? String(localized: "\(program.title) (recommended)") : program.title).tag(program)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Text(summary(of: selected, profile: profile)).font(.subheadline)
            if profile.bmi == nil {
                NavigationLink { BMIView() } label: {
                    Label("Add your height and weight for a plan that fits your weight", systemImage: "scalemass")
                        .font(.subheadline)
                }
            }
            Button {
                model.startPlan(selected, averageSteps: averageSteps)
                if !Reminders.isOn { offeringReminder = true }
                Task { await model.refreshReminders() }
            } label: {
                Text("Start \(selected.title) today").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Check with your doctor before starting if you have a heart, lung or joint condition, are pregnant, or haven't been active for a long time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func reason(for program: TrainingPlan.Program, profile: Profile) -> String {
        var facts = [String(localized: "age \(profile.age)")]
        if let bmi = profile.bmi {
            facts.insert(String(localized: "BMI \(bmi.formatted(.number.precision(.fractionLength(1)))) (\(BMI.category(bmi).label.lowercased()))"), at: 0)
        }
        if !profile.limitations.isEmpty {
            facts.append(String(localized: "your \(profile.limitations.map(\.shortLabel).sorted().joined(separator: ", ")) notes"))
        }
        let why: String = switch program {
        case .runWalk: String(localized: "you can build up to running safely")
        case .briskWalk: String(localized: "brisk walking burns fat while being kind to your joints")
        case .gentleWalk: String(localized: "a gentle start builds fitness safely")
        }
        return String(localized: "Based on your \(facts.joined(separator: ", ")), we recommend this plan: \(why).")
    }

    private func summary(of program: TrainingPlan.Program, profile: Profile) -> String {
        let loss = TrainingPlan.aimsForWeightLoss(profile)
        switch program {
        case .runWalk:
            return String(localized: "9 weeks, 3 run/walk sessions a week (about 30 min), building from 1-minute runs to 30 minutes of running, plus 2 strength days.")
        case .briskWalk:
            return String(localized: "12 weeks of brisk walking on 5 days, from 20 minutes up to \(loss ? "50" : "30") a day (\(loss ? "250" : "150") min a week), plus 2 strength days.")
        case .gentleWalk:
            return String(localized: "12 weeks of easy walking on 5 days, from 10 minutes up to \(loss ? "50" : "30") a day, plus 2 gentle strength days with a chair.")
        }
    }

    // MARK: - The week

    private func weekHeader(_ week: TrainingPlan.Week, finished: Bool) -> some View {
        let doneDays = week.days.filter { model.isPlanDayDone(date(ofDay: $0.index, week: model.planPosition()?.week ?? 1)) }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(week.program.title).font(.display(.title3))
                    Text(finished ? "Plan complete: keep repeating the final week" : "Week \(week.number) of \(week.program.weeks)")
                        .font(.subheadline).opacity(0.9)
                }
                Spacer()
                ArcGauge(progress: Double(doneDays) / 7, lineWidth: 8) {
                    Text("\(doneDays)/7").font(.metric(15))
                }
                .frame(width: 70)
            }
            HStack(spacing: 10) {
                goal("\(week.aerobicMinutes)", "active min", sub: "goal \(week.targetMinutes)+")
                goal(week.stepGoal.formatted(), "steps a day", sub: "today \(steps.today.formatted())")
                goal("\(week.sets) × \(week.reps)", "sets × reps", sub: "2 days")
            }
        }
        .heroCard(.plan)
    }

    private func goal(_ value: String, _ label: LocalizedStringKey, sub: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.metric(20))
            Text(label).font(.caption)
            Text(sub).font(.caption2).opacity(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func dayCard(_ day: TrainingPlan.Day, week: TrainingPlan.Week, date: Date, isToday: Bool) -> some View {
        let done = model.isPlanDayDone(date)
        let canTick = date <= Date()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isToday ? String(localized: "Today") : date.formatted(.dateTime.weekday(.wide)))
                    .font(.display(.headline))
                    .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                Text(date.formatted(.dateTime.day().month())).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if canTick {
                    Button {
                        model.setPlanDay(date, done: !done)
                        Task { await model.refreshReminders() }
                    } label: {
                        Label(done ? "Done" : "Mark done", systemImage: done ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(done ? Color.green : Color.secondary)
                }
            }
            ForEach(Array(day.activities.enumerated()), id: \.offset) { _, activity in
                activityRow(activity, week: week, isToday: isToday)
            }
            if day.activities != [.rest] {
                Label("Aim for \(day.stepGoal.formatted()) steps", systemImage: "figure.walk")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .tintedCard(isToday ? .plan : .glance)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Feature.plan.gradient, lineWidth: isToday ? 2.5 : 0))
    }

    @ViewBuilder
    private func activityRow(_ activity: TrainingPlan.Activity, week: TrainingPlan.Week, isToday: Bool) -> some View {
        switch activity {
        case .cardio(let program, let intervals):
            let title = TrainingPlan.cardioName(program, intervals)
            row(icon: program == .runWalk ? "figure.run" : "figure.walk", title: String(localized: "\(title) · \(activity.minutes) min"),
                detail: String(localized: "\(TrainingPlan.describe(intervals)) · ≈ \(activity.steps.formatted()) steps"),
                start: isToday ? { cardio = CardioWorkout(title: String(localized: "\(title), week \(week.number)"), intervals: intervals) } : nil)
        case .strength(let sets, let moves):
            row(icon: "dumbbell.fill", title: sets == 1 ? String(localized: "Strength · 1 set") : String(localized: "Strength · \(sets) sets"),
                detail: String(localized: "\(describe(moves)). Rest 1 minute between sets."),
                start: isToday ? { session = StrengthSession(items: TrainingPlan.sessionItems(sets: sets, moves: moves)) } : nil)
        case .balance(let sets, let moves):
            row(icon: "figure.stand", title: sets == 1 ? String(localized: "Balance · 1 set") : String(localized: "Balance · \(sets) sets"),
                detail: String(localized: "\(describe(moves)). Hold a wall or chair if you need to."),
                start: isToday ? { session = StrengthSession(items: TrainingPlan.sessionItems(sets: sets, moves: moves)) } : nil)
        case .rest:
            row(icon: "bed.double.fill", title: String(localized: "Rest day"),
                detail: String(localized: "Recovery is part of training. A gentle stroll or stretching is fine."), start: nil)
        }
    }

    private func row(icon: String, title: String, detail: String, start: (() -> Void)?) -> some View {
        let feature: Feature = switch icon {
        case "dumbbell.fill": .plan
        case "figure.stand": .bmi
        case "bed.double.fill": .sleep
        default: .steps
        }
        return HStack(alignment: .top, spacing: 12) {
            FeatureBadge(feature: feature, symbol: icon, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let start {
                Button("Start", action: start)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private func describe(_ moves: [TrainingPlan.StrengthMove]) -> String {
        moves.map { move in
            let name = ExerciseLibrary.shared[move.exerciseID].name
            if let reps = move.reps { return String(localized: "\(name) × \(reps)") }
            return String(localized: "\(name) \(move.seconds ?? 30) s")
        }
        .joined(separator: ", ")
    }

    // MARK: - Sources

    private var sources: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Where these numbers come from", systemImage: "books.vertical").font(.display(.headline))
            source("WHO guidelines on physical activity (2020)", "150–300 active minutes a week, strength on 2+ days, balance on 3+ days from 65.",
                   "https://www.who.int/publications/i/item/9789240015128")
            source("NHS Couch to 5K", "9 weeks, 3 run/walk sessions a week building to 30 minutes of running.",
                   "https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/")
            source("American College of Sports Medicine (2009)", "More than 250 min a week for weight loss; beginners train strength 2–3 days, 8–12 reps, 1–3 sets.",
                   "https://pubmed.ncbi.nlm.nih.gov/19127177/")
            source("Paluch et al., Lancet Public Health (2022)", "Benefits of walking level off at 8,000–10,000 steps a day under 60, and 6,000–8,000 from 60.",
                   "https://pubmed.ncbi.nlm.nih.gov/35247352/")
            Text("A general fitness plan, not medical advice. Stop and rest if anything hurts, and seek help for chest pain, dizziness or severe breathlessness.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func source(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, _ url: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let link = URL(string: url) {
                Link(title, destination: link).font(.subheadline.weight(.semibold))
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var averageSteps: Int? {
        // The iPhone counts its owner's steps; a family member's goals start from the defaults.
        guard model.isOwner else { return nil }
        let past = steps.week.dropLast().map(\.steps).filter { $0 > 0 }
        return past.isEmpty ? nil : past.reduce(0, +) / past.count
    }

    private func date(ofDay day: Int, week: Int) -> Date {
        let start = model.planStart ?? Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: (week - 1) * 7 + day, to: start) ?? start
    }
}

private struct CardioWorkout: Identifiable {
    let id = UUID()
    let title: String
    let intervals: [TrainingPlan.Interval]
}

private struct StrengthSession: Identifiable {
    let id = UUID()
    let items: [PlanItem]
}

// MARK: - Guided run/walk

/// Talks you through a walk or run/walk: announces each interval, counts down, and shows your
/// steps. Keeps the screen on while it runs.
struct IntervalWorkoutView: View {
    let title: String
    let intervals: [TrainingPlan.Interval]
    var onFinish: () -> Void = {}

    @EnvironmentObject private var voice: VoiceCoach
    @EnvironmentObject private var steps: StepCounter
    @Environment(\.dismiss) private var dismiss
    @State private var elapsed: TimeInterval = 0
    @State private var running = false
    @State private var started = false
    @State private var announced = -1
    @State private var finished = false
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var total: TimeInterval { TimeInterval(intervals.reduce(0) { $0 + $1.seconds }) }

    /// The current interval and seconds left in it.
    private var position: (index: Int, left: TimeInterval) {
        var t = elapsed
        for (i, interval) in intervals.enumerated() {
            if t < TimeInterval(interval.seconds) { return (i, TimeInterval(interval.seconds) - t) }
            t -= TimeInterval(interval.seconds)
        }
        return (intervals.count - 1, 0)
    }

    var body: some View {
        let (index, left) = position
        let current = intervals[index]
        VStack(spacing: 22) {
            HStack {
                Button { stop() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44) }
                Text(title).font(.headline)
                Spacer()
                MusicButton()
            }
            Spacer()
            Text(finished ? String(localized: "Well done!") : current.title)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(color(current.kind))
            ProgressRing(progress: finished ? 1 : 1 - left / TimeInterval(current.seconds), color: color(current.kind), lineWidth: 18) {
                VStack(spacing: 4) {
                    Text(clock(finished ? 0 : left)).font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("Interval \(index + 1) of \(intervals.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 250, height: 250)
            if !finished, index + 1 < intervals.count {
                Text("Next: \(intervals[index + 1].title) \(clock(TimeInterval(intervals[index + 1].seconds)))")
                    .font(.headline).foregroundStyle(.secondary)
            }
            ProgressView(value: min(elapsed, total), total: total).tint(.accentColor).padding(.horizontal)
            HStack(spacing: 28) {
                stat(clock(elapsed), "elapsed")
                stat(clock(max(total - elapsed, 0)), "left")
                stat(steps.today.formatted(), "steps today")
            }
            Spacer()
            controls
        }
        .padding()
        .background(AppBackground())
        .onReceive(tick) { _ in advance() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private var controls: some View {
        if finished {
            Button { dismiss() } label: { Text("Finish").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else if !started {
            Button {
                started = true
                running = true
            } label: { Text("Start").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            HStack(spacing: 12) {
                Button(running ? "Pause" : "Resume") {
                    running.toggle()
                    voice.say(running ? String(localized: "Let's go.") : String(localized: "Paused."), interrupt: true)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                Button("Skip interval") { skip() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }

    private func advance() {
        guard running, !finished else { return }
        elapsed += 0.25
        let index = position.index
        if index != announced {
            announced = index
            voice.say(Self.announcement(intervals[index], isFirst: index == 0), interrupt: true)
        }
        if elapsed >= total {
            finished = true
            running = false
            voice.say(String(localized: "That's it, well done! Walking and running like this is how fitness builds."), interrupt: true)
            onFinish()
        }
    }

    private func skip() {
        let (index, left) = position
        guard index + 1 < intervals.count else { elapsed = total; return }
        elapsed += left
    }

    private func stop() {
        voice.stop()
        dismiss()
    }

    /// "Run for a minute and a half."
    static func announcement(_ interval: TrainingPlan.Interval, isFirst: Bool) -> String {
        let length = spoken(interval.seconds)
        switch interval.kind {
        case .warmUp: return String(localized: "Warm up with a \(length) walk at an easy pace.")
        case .coolDown: return String(localized: "Great work. Cool down with a \(length) easy walk.")
        case .run: return String(localized: "Run for \(length). Keep it slow enough to talk.")
        case .walk: return String(localized: "Walk for \(length).")
        case .brisk: return String(localized: "Now walk briskly for \(length). You should be able to talk, but not sing.")
        case .easy: return String(localized: "Easy walk for \(length).")
        }
    }

    static func spoken(_ seconds: Int) -> String {
        let minutes = seconds / 60, rest = seconds % 60
        switch (minutes, rest) {
        case (0, _): return String(localized: "\(rest) seconds")
        case (1, 0): return String(localized: "1 minute")
        case (1, 30): return String(localized: "a minute and a half")
        case (_, 0): return String(localized: "\(minutes) minutes")
        case (_, 30): return String(localized: "\(minutes) and a half minutes")
        default: return String(localized: "\(minutes) minutes \(rest) seconds")
        }
    }

    private func color(_ kind: TrainingPlan.Interval.Kind) -> Color {
        kind == .run ? .accentColor : Color(red: 0.13, green: 0.6, blue: 0.55)
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Summary card

/// Today's part of the training plan, or an invitation to get one. Opens `PlanView`.
struct TrainingPlanCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: Store

    var body: some View {
        if store.hasPlus {
            card
        } else {
            PlusLockedCard(feature: .plan)
        }
    }

    private var card: some View {
        NavigationLink { PlanView() } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    if let profile = model.profile, let program = model.planProgram, let position = model.planPosition() {
                        let week = TrainingPlan.week(position.week, program: program, profile: profile, averageSteps: model.planBaseSteps)
                        let today = week.days[position.day]
                        Text("\(program.title) · week \(min(position.week, program.weeks))").font(.caption).opacity(0.85)
                        Text(TrainingPlan.headline(today)).font(.display(.title3)).multilineTextAlignment(.leading)
                        if model.isPlanDayDone(Date()) {
                            Label("Done for today", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold))
                        } else if today.activities != [.rest] {
                            Text("Aim for \(today.stepGoal.formatted()) steps").font(.caption).opacity(0.85)
                        }
                    } else {
                        Text("Your training plan").font(.display(.title3))
                        Text("Walking or running, strength sets and daily steps, built for your weight and age.")
                            .font(.subheadline).opacity(0.9).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").opacity(0.7)
            }
            .heroCard(.plan)
        }
        .buttonStyle(.plain)
    }
}

