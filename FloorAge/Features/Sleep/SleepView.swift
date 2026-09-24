import Charts
import HealthKit
import SwiftUI

/// Reads sleep from Apple Health (read only; nothing is written or sent anywhere).
enum HealthSleep {
    private static let store = HKHealthStore()
    private static let type = HKCategoryType(.sleepAnalysis)
    /// HKCategoryValueSleepAnalysis: 0 in bed, 2 awake, 1/3/4/5 asleep (unspecified, core, deep, REM).
    private static let asleepValues: Set<Int> = [1, 3, 4, 5]

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: "healthSleep") }
        set { UserDefaults.standard.set(newValue, forKey: "healthSleep") }
    }

    static func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        return (try? await store.requestAuthorization(toShare: [], read: [type])) != nil
    }

    /// The last `days` nights from Health, merged into one entry per night.
    static func nights(days: Int = 21) async -> [SleepEntry] {
        guard isAvailable, let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: Date()))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return SleepGuide.nights(from: samples.compactMap { sample in
            guard sample.value != 2 else { return nil }  // awake
            return SleepGuide.Sample(start: sample.startDate, end: sample.endDate, asleep: asleepValues.contains(sample.value))
        })
    }
}

/// Last night, the past two weeks against the recommended range, a quick morning log and Apple
/// Health import.
struct SleepView: View {
    @EnvironmentObject private var model: AppModel
    @State private var bedtime = SleepView.defaultTime(hour: 23, minute: 0, daysAgo: 1)
    @State private var wake = SleepView.defaultTime(hour: 6, minute: 30, daysAgo: 0)
    @State private var quality = 2
    @State private var healthOn = HealthSleep.isOn
    @State private var saved = false

    var body: some View {
        let age = model.profile?.age ?? 40
        let range = SleepGuide.recommended(age: age)
        let nights = model.recentSleep(days: 14)
        List {
            Section {
                VStack(spacing: Space.m) {
                    if let last = model.sleepLog.last {
                        Text(Calendar.current.isDateInToday(last.day) ? String(localized: "Last night") : last.day.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline).opacity(0.85)
                        Text(SleepGuide.duration(last.hours))
                            .font(.metric(44))
                        Text("\(last.bedtime.formatted(date: .omitted, time: .shortened)) – \(last.wake.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline).opacity(0.85)
                        Text(SleepGuide.assessment(hours: last.hours, age: age))
                            .font(.subheadline).multilineTextAlignment(.center)
                    } else {
                        Image(systemName: "moon.stars.fill").font(.largeTitle)
                        Text("Log how you slept to see your nights here.").font(.subheadline).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .heroCard(.sleep, padding: Space.xl)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 10, trailing: 0))
            }

            if !nights.isEmpty {
                Section {
                    Chart {
                        RectangleMark(yStart: .value("From", range.lowerBound), yEnd: .value("To", range.upperBound))
                            .foregroundStyle(Color.green.opacity(0.12))
                        ForEach(nights) { night in
                            BarMark(x: .value("Night", night.day, unit: .day), y: .value("Hours", night.hours))
                                .foregroundStyle(range.contains(night.hours) ? Feature.sleep.gradient : Feature.steps.gradient)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .chartYScale(domain: 0...max(10, (nights.map(\.hours).max() ?? 0) + 1))
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day()) } }
                    .frame(height: 170)
                    if let average = model.averageSleep {
                        LabeledContent("7-night average", value: SleepGuide.duration(average))
                    }
                } header: {
                    Text("Last 2 weeks")
                } footer: {
                    Text("The green band is the recommended \(SleepGuide.label(range)) for your age (National Sleep Foundation).")
                }
            }

            Section {
                DatePicker("Went to bed", selection: $bedtime, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Woke up", selection: $wake, displayedComponents: [.date, .hourAndMinute])
                Picker("How did you sleep?", selection: $quality) {
                    Text("Poorly").tag(1)
                    Text("OK").tag(2)
                    Text("Well").tag(3)
                }
                .pickerStyle(.segmented)
                Button(saved ? "Saved" : "Save this night") {
                    model.logSleep(SleepEntry(bedtime: bedtime, wake: wake, quality: quality))
                    saved = true
                }
                .font(.headline)
                .disabled(wake <= bedtime || wake.timeIntervalSince(bedtime) > 16 * 3600 || saved)
            } header: {
                Text("Log a night")
            }
            .onChange(of: bedtime) { saved = false }
            .onChange(of: wake) { saved = false }

            if HealthSleep.isAvailable, model.isOwner {
                Section {
                    Toggle("Read sleep from Apple Health", isOn: $healthOn)
                        .onChange(of: healthOn) { _, on in
                            HealthSleep.isOn = on
                            if on { Task { await importFromHealth(asking: true) } }
                        }
                } footer: {
                    Text("Uses the sleep your iPhone's Sleep schedule or an Apple Watch records. Floor Age only reads it, and it stays on your phone. Nights you log yourself are kept.")
                }
            }

            Section("Sleeping better") {
                Label("Keep the same bedtime and wake time, even at weekends.", systemImage: "clock")
                Label("Put screens away an hour before bed.", systemImage: "iphone.slash")
                Label("No caffeine after mid-afternoon.", systemImage: "cup.and.saucer")
                Label("Daytime activity, like your walks, helps you fall asleep.", systemImage: "figure.walk")
            }
            .font(.subheadline)

            if !model.sleepLog.isEmpty {
                Section("Nights") {
                    ForEach(model.sleepLog.reversed()) { night in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(night.day.formatted(date: .abbreviated, time: .omitted))
                                Text(night.fromHealth ? "Apple Health"
                                     : [String(localized: "Logged"), String(localized: "Slept poorly"), String(localized: "Slept OK"), String(localized: "Slept well")][night.quality ?? 0])
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(SleepGuide.duration(night.hours)).monospacedDigit()
                        }
                    }
                    .onDelete { offsets in
                        let reversed = Array(model.sleepLog.reversed())
                        offsets.map { reversed[$0].id }.forEach(model.removeSleep)
                    }
                }
            }
        }
        .appBackground()
        .navigationTitle("Sleep")
        .task { if healthOn, model.isOwner { await importFromHealth(asking: false) } }
    }

    private func importFromHealth(asking: Bool) async {
        if asking, !(await HealthSleep.requestAccess()) { return }
        let nights = await HealthSleep.nights()
        if !nights.isEmpty { model.importSleep(nights) }
    }

    static func defaultTime(hour: Int, minute: Int, daysAgo: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

/// Last night's sleep and the weekly average, for the Track tab.
struct SleepCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let age = model.profile?.age ?? 40
        let range = SleepGuide.recommended(age: age)
        HStack(spacing: Space.l) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Sleep", systemImage: "moon.stars.fill").font(.headline)
                if let last = model.sleepLog.last, Calendar.current.isDateInToday(last.day) || Calendar.current.isDateInYesterday(last.day) {
                    Text(SleepGuide.duration(last.hours)).font(.metric(30))
                } else {
                    Text("How did you sleep?").font(.title3.weight(.semibold))
                }
                if let average = model.averageSleep {
                    Text("7-night average \(SleepGuide.duration(average)) · goal \(SleepGuide.label(range))")
                        .font(.caption).opacity(0.85)
                } else {
                    Text("Goal \(SleepGuide.label(range)) a night").font(.caption).opacity(0.85)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").opacity(0.7)
        }
        .heroCard(.sleep)
    }
}
