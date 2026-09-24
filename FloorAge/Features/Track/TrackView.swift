import Charts
import SwiftUI

/// Everyday tracking: steps, food calories, BMI and sleep. Everything stays on the phone.
struct TrackView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var steps: StepCounter
    @EnvironmentObject private var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    glance
                    TrainingPlanCard()
                    if model.isOwner {
                        NavigationLink { StepsView() } label: { stepsCard }
                    }
                    NavigationLink { FoodLogView() } label: { caloriesCard }
                    NavigationLink { BMIView() } label: { bmiCard }
                    if store.hasPlus {
                        NavigationLink { SleepView() } label: { SleepCard() }
                    } else {
                        PlusLockedCard(feature: .sleep)
                    }
                    Text("Estimates for everyday fitness, not medical advice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding()
            }
            .background(AppBackground())
            .navigationTitle("Track")
            .onAppear { steps.start() }
        }
    }

    /// Steps, calories and last night's sleep in one colourful strip.
    private var glance: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                Text("Today at a glance").font(.display(.title3))
                Spacer()
                Text(Date().formatted(.dateTime.weekday(.wide).day().month())).font(.subheadline).opacity(0.85)
            }
            HStack(spacing: 0) {
                if model.isOwner {
                    glanceItem(steps.today.formatted(), "Steps", symbol: "figure.walk")
                } else {
                    // This iPhone counts its owner's steps, so family members see their Floor Age instead.
                    glanceItem(model.latestResult.map { "\($0.floorAge)" } ?? "–", "Floor Age", symbol: "figure.cross.training")
                }
                Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 44)
                glanceItem(model.caloriesEaten().formatted(), "kcal", symbol: "flame.fill")
                Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 44)
                glanceItem(model.sleepLog.last.map { SleepGuide.duration($0.hours) } ?? "–", "Sleep", symbol: "moon.fill")
            }
        }
        .heroCard(.glance)
    }

    private func glanceItem(_ value: String, _ label: LocalizedStringKey, symbol: String) -> some View {
        VStack(spacing: Space.xs) {
            Image(systemName: symbol).font(.subheadline).opacity(0.9)
            Text(value).font(.metric(20)).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).opacity(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Label("Steps", systemImage: "figure.walk").font(.headline)
                Spacer()
                Image(systemName: "chevron.right").opacity(0.7)
            }
            switch steps.status {
            case .unavailable:
                Text("Not available on this device").font(.headline)
            case .denied:
                Text("Allow Motion & Fitness").font(.headline)
                Text("iPhone Settings › Privacy & Security").font(.caption).opacity(0.85)
            default:
                HStack(alignment: .bottom, spacing: Space.m) {
                    ArcGauge(progress: steps.progress) {
                        VStack(spacing: 0) {
                            Text(steps.today.formatted()).font(.metric(30))
                            Text("of \(steps.goal.formatted()) · \(Steps.distance(steps.today))").font(.caption2).opacity(0.9)
                        }
                    }
                    .frame(width: 180)
                    Spacer(minLength: 0)
                    WeekBars(days: steps.week, goal: steps.goal, color: .white)
                        .frame(width: 96, height: 58)
                }
                // Grey placeholders until the first count arrives, so the numbers don't jump in.
                .redacted(reason: steps.isLoading ? .placeholder : [])
            }
        }
        .heroCard(.steps)
    }

    private var caloriesCard: some View {
        let eaten = model.caloriesEaten()
        let target = model.profile?.calorieTarget
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                FeatureBadge(feature: .calories)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Calories").font(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(eaten.formatted()).font(.metric(28))
                        Text("kcal eaten today").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            if let target {
                GradientBar(progress: Double(eaten) / Double(max(target, 1)), colors: eaten > target ? Feature.steps.colors : Feature.calories.colors)
                HStack {
                    Text("Daily target about \(target.formatted()) kcal").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    let left = target - eaten
                    Text(left >= 0 ? "\(left.formatted()) left" : "\((-left).formatted()) over")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(left >= 0 ? Feature.calories.inkColors[1] : Feature.steps.inkColors[1])
                }
            } else {
                Text("Add your height and weight under BMI to get a daily target.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .tintedCard(.calories)
    }

    private var bmiCard: some View {
        HStack(spacing: Space.m) {
            FeatureBadge(feature: .bmi)
            if let bmi = model.profile?.bmi {
                let category = BMI.category(bmi)
                VStack(alignment: .leading, spacing: 0) {
                    Text("BMI").font(.subheadline).foregroundStyle(.secondary)
                    Text(bmi, format: .number.precision(.fractionLength(1))).font(.metric(28))
                }
                Text(category.label)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
                    .background(category.color.gradient, in: Capsule())
                    .foregroundStyle(.white)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BMI calculator").font(.headline)
                    Text("Enter your height and weight").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .tintedCard(.bmi)
    }
}

/// A rounded progress bar filled with a gradient.
struct GradientBar: View {
    var progress: Double
    var colors: [Color]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(colors[0].opacity(0.15))
                .overlay(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * min(max(progress, 0), 1))
                        .shadow(color: colors.last!.opacity(0.4), radius: 4)
                }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.6), value: progress)
    }
}

extension BMI.Category {
    var color: Color {
        switch self {
        case .underweight: .blue
        case .healthy: .green
        case .overweight: .orange
        case .obese: .red
        }
    }
}

// MARK: - Shared pieces

struct ProgressRing<Label: View>: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 9
    @ViewBuilder var label: Label

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            label
        }
    }
}

/// Seven small bars for the week, today's highlighted.
struct WeekBars: View {
    let days: [StepCounter.Day]
    let goal: Int
    var color: Color = .accentColor

    var body: some View {
        if days.isEmpty {
            // Still loading: seven even bars hold the space.
            HStack(alignment: .bottom, spacing: Space.xs) {
                ForEach(0..<7, id: \.self) { _ in Capsule().fill(color.opacity(0.25)) }
            }
            .padding(.top, Space.l)
        } else {
            Chart(days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.steps))
                    .foregroundStyle(Calendar.current.isDateInToday(day.date) ? color : color.opacity(day.steps >= goal ? 0.65 : 0.35))
                    .clipShape(Capsule())
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
    }
}

// MARK: - Steps

struct StepsView: View {
    @EnvironmentObject private var steps: StepCounter

    var body: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                VStack(spacing: Space.l) {
                    ArcGauge(progress: steps.progress, lineWidth: 20) {
                        VStack(spacing: 0) {
                            Text(steps.today.formatted()).font(.metric(46))
                            Text("steps today").font(.subheadline).opacity(0.9)
                        }
                    }
                    .frame(maxWidth: 280)
                    HStack(spacing: Space.m) {
                        stat(Steps.distance(steps.today), "distance")
                        stat("\(max(steps.goal - steps.today, 0).formatted())", "to your goal")
                        stat("\(Int(Double(steps.today) * 0.04).formatted())", "kcal burned")
                    }
                }
                .frame(maxWidth: .infinity)
                .redacted(reason: steps.isLoading ? .placeholder : [])
                .heroCard(.steps, padding: Space.xl)

                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Last 7 days").font(.display(.title3))
                    Chart {
                        ForEach(steps.week) { day in
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.steps))
                                .foregroundStyle(day.steps >= steps.goal ? Feature.calories.gradient : Feature.steps.gradient)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        RuleMark(y: .value("Goal", steps.goal))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                            .annotation(position: .top, alignment: .leading) {
                                Text("Goal").font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    }
                    .frame(height: 180)
                }
                .tintedCard(.steps)

                VStack(alignment: .leading, spacing: Space.m) {
                    Stepper("Daily goal: \(steps.goal.formatted())", value: $steps.goal, in: 2000...20000, step: 500)
                        .font(.headline)
                    Text("About 7,000–8,000 steps a day is linked with good health. A brisk 10-minute walk is roughly 1,000 steps. Missing a day never resets your progress.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if steps.status == .denied {
                        Label("Step counting is off. Turn on Motion & Fitness for Floor Age in iPhone Settings › Privacy & Security.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    } else if steps.status == .unavailable {
                        Label("This device can't count steps.", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                .tintedCard(.steps)
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle("Steps")
        .onAppear { steps.start() }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.metric(17)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).opacity(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }
}

// MARK: - Food

struct FoodLogView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: Store
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var adding = false
    @State private var snapping = false
    @State private var showingPlus = false

    var body: some View {
        let entries = model.foods(on: day)
        let eaten = model.caloriesEaten(on: day)
        let target = model.profile?.calorieTarget
        List {
            Section {
                HStack(spacing: Space.l) {
                    ArcGauge(progress: target.map { Double(eaten) / Double($0) } ?? 0, lineWidth: 14) {
                        VStack(spacing: 0) {
                            Text(eaten.formatted()).font(.metric(28))
                            Text("kcal").font(.caption).opacity(0.9)
                        }
                    }
                    .frame(width: 150)
                    VStack(alignment: .leading, spacing: Space.s) {
                        if let target {
                            Text("Target \(target.formatted()) kcal").font(.headline)
                            let left = target - eaten
                            Text(left >= 0 ? "\(left.formatted()) kcal left" : "\((-left).formatted()) kcal over")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
                                .background(.white.opacity(left >= 0 ? 0.22 : 0.35), in: Capsule())
                        } else {
                            Text("No daily target yet").font(.headline)
                            NavigationLink("Add height and weight") { BMIView() }
                                .font(.subheadline.weight(.semibold))
                                .underline()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .heroCard(eaten > (target ?? .max) ? .steps : .calories)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 10, trailing: 0))
            } header: {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(dayTitle).font(.subheadline.weight(.semibold)).textCase(nil)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(Calendar.current.isDateInToday(day))
                }
            }

            Section {
                if entries.isEmpty {
                    Text("Nothing logged yet.").foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.displayName)
                            Text(servingsLabel(entry)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(entry.total) kcal").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    offsets.map { entries[$0].id }.forEach(model.removeFood)
                }
                Button(action: snap) {
                    HStack {
                        Label("Snap your plate", systemImage: "camera.fill").font(.headline)
                        if !store.hasPlus {
                            Spacer()
                            PlusBadge()
                        }
                    }
                }
                Button { adding = true } label: {
                    Label("Add food", systemImage: "plus.circle.fill").font(.headline)
                }
            } header: {
                Text("Food")
            } footer: {
                Text("Calories are typical values for home portions and vary with recipe and oil.")
            }
        }
        .appBackground()
        .navigationTitle("Calories")
        .sheet(isPresented: $adding) {
            AddFoodView(day: day)
        }
        .sheet(isPresented: $snapping) {
            FoodPhotoView(day: day)
        }
        .sheet(isPresented: $showingPlus) {
            PlusView(highlight: .foodPhoto).environmentObject(store)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Snap your plate", systemImage: "camera", action: snap)
            }
        }
    }

    /// Food photos are part of Floor Age Plus.
    private func snap() {
        if store.hasPlus { snapping = true } else { showingPlus = true }
    }

    private var dayTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return String(localized: "Today") }
        if cal.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    private func shift(_ days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: day), next <= Date() { day = next }
    }

    private func servingsLabel(_ entry: FoodEntry) -> String {
        let count = entry.servings == entry.servings.rounded() ? String(localized: "\(Int(entry.servings))") : String(format: "%.1f", entry.servings)
        return String(localized: "\(count) × \(entry.kcal) kcal")
    }
}

struct AddFoodView: View {
    let day: Date
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var picked: FoodItem?
    @State private var servings = 1.0
    @State private var customName = ""
    @State private var customKcal = ""

    var body: some View {
        NavigationStack {
            List {
                if let picked {
                    Section("Add \(picked.displayName)") {
                        Stepper("Servings: \(servings.formatted()) × \(picked.displayServing)", value: $servings, in: 0.5...10, step: 0.5)
                        LabeledContent("Calories", value: "\(Int((Double(picked.kcal) * servings).rounded())) kcal")
                        Button("Add to log") {
                            add(FoodEntry(date: timestamp, name: picked.name, kcal: picked.kcal, servings: servings))
                        }
                        .font(.headline)
                    }
                }
                Section("Common foods") {
                    ForEach(FoodLibrary.search(search)) { item in
                        Button {
                            picked = item
                            servings = 1
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.displayName).foregroundStyle(Color.primary)
                                    Text(item.displayServing).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(item.kcal) kcal").monospacedDigit().foregroundStyle(.secondary)
                                if picked == item { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                            }
                        }
                    }
                }
                Section("Something else") {
                    TextField("Food name", text: $customName)
                    TextField("Calories (kcal)", text: $customKcal)
                        .keyboardType(.numberPad)
                    Button("Add to log") {
                        guard let kcal = Int(customKcal), kcal > 0 else { return }
                        add(FoodEntry(date: timestamp, name: customName.trimmingCharacters(in: .whitespaces), kcal: kcal))
                    }
                    .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty || (Int(customKcal) ?? 0) <= 0)
                }
            }
            .searchable(text: $search, prompt: "Search roti, dal, idli…")
            .appBackground()
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    /// Now for today; midday for an earlier day being filled in.
    private var timestamp: Date {
        Calendar.current.isDateInToday(day) ? Date() : Calendar.current.date(byAdding: .hour, value: 12, to: day) ?? day
    }

    private func add(_ entry: FoodEntry) {
        model.addFood(entry)
        dismiss()
    }
}

// MARK: - BMI

struct BMIView: View {
    @EnvironmentObject private var model: AppModel
    @State private var metricHeight = true
    @State private var heightCm = 165.0
    @State private var feet = 5
    @State private var inches = 5
    @State private var weightKg = 65.0
    @State private var pounds = Region.usesPounds
    @State private var scale = BMIScale.current

    var body: some View {
        let height = metricHeight ? heightCm : BMI.centimetres(feet: feet, inches: inches)
        let bmi = BMI.value(weightKg: weightKg, heightCm: height) ?? 0
        let category = BMI.category(bmi, scale: scale)
        Form {
            Section {
                VStack(spacing: Space.l) {
                    Text(bmi, format: .number.precision(.fractionLength(1)))
                        .font(.metric(60))
                        .contentTransition(.numericText())
                    Text(category.label)
                        .font(.headline)
                        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                        .background(category.color.gradient, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    BMIGauge(bmi: bmi, scale: scale)
                        .frame(height: 34)
                    Text(category.message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    let range = BMI.healthyWeight(heightCm: height, scale: scale)
                    Text("A healthy weight for your height is about \(weightText(range.lowerBound, decimals: false))–\(weightText(range.upperBound, decimals: false)).")
                        .font(.footnote)
                        .opacity(0.85)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .heroCard(.bmi, padding: Space.xl)
                .animation(.snappy, value: bmi)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 10, trailing: 0))
            }

            Section("Height") {
                Picker("Units", selection: $metricHeight) {
                    Text("cm").tag(true)
                    Text("ft / in").tag(false)
                }
                .pickerStyle(.segmented)
                if metricHeight {
                    Stepper("\(Int(heightCm)) cm", value: $heightCm, in: 120...220, step: 1)
                } else {
                    Stepper("\(feet) ft", value: $feet, in: 4...7)
                    Stepper("\(inches) in", value: $inches, in: 0...11)
                }
            }

            Section("Weight") {
                Picker("Units", selection: $pounds) {
                    Text("kg").tag(false)
                    Text("lb").tag(true)
                }
                .pickerStyle(.segmented)
                Stepper(weightText(weightKg, decimals: true), value: $weightKg, in: 30...200, step: pounds ? BMI.kilograms(pounds: 1) : 0.5)
                Slider(value: $weightKg, in: 30...150, step: pounds ? BMI.kilograms(pounds: 1) : 0.5)
            }

            Section {
                Picker("BMI ranges", selection: $scale) {
                    ForEach(BMIScale.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: scale) { _, value in BMIScale.current = value }
            } footer: {
                Text(scale == .asian
                     ? "Asian ranges (healthy 18.5–22.9) are recommended for people of Asian descent, whose health risks start at a lower BMI."
                     : "WHO international ranges: healthy 18.5–24.9. If you're of South Asian, Chinese or other Asian descent, the Asian ranges fit better.")
            }

            Section {
                let saved = isSaved(height: height)
                Button(saved ? "Saved to your profile" : "Save to my profile") {
                    model.updateBody(heightCm: height, weightKg: weightKg)
                }
                .font(.headline)
                .disabled(saved)
            } footer: {
                Text("BMI doesn't account for muscle, so treat it as a rough guide, not a diagnosis.")
            }

            if model.weights.count >= 2 {
                Section("Weight over time") {
                    Chart(model.weights, id: \.date) { entry in
                        LineMark(x: .value("Date", entry.date), y: .value("Weight", pounds ? BMI.pounds(entry.kg) : entry.kg))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", entry.date), y: .value("Weight", pounds ? BMI.pounds(entry.kg) : entry.kg))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                }
            }
        }
        .appBackground()
        .navigationTitle("BMI")
        .onAppear(perform: load)
    }

    private func weightText(_ kg: Double, decimals: Bool) -> String {
        let value = pounds ? BMI.pounds(kg) : kg
        let number = decimals && !pounds ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
        return "\(number) \(pounds ? "lb" : "kg")"
    }

    private func isSaved(height: Double) -> Bool {
        guard let h = model.profile?.heightCm, let w = model.profile?.weightKg else { return false }
        return abs(h - height) < 0.5 && abs(w - weightKg) < 0.05
    }

    private func load() {
        if let h = model.profile?.heightCm {
            heightCm = h.rounded()
            (feet, inches) = BMI.feetAndInches(h)
        }
        if let w = model.profile?.weightKg { weightKg = w }
    }
}

/// Coloured bands for the four BMI categories with a marker at this BMI.
struct BMIGauge: View {
    let bmi: Double
    var scale: BMIScale = .current
    private var bands: [(BMI.Category, ClosedRange<Double>)] {
        [(.underweight, 15...BMI.underweightBelow), (.healthy, BMI.underweightBelow...scale.overweight),
         (.overweight, scale.overweight...scale.obese), (.obese, scale.obese...35)]
    }

    var body: some View {
        GeometryReader { geo in
            let lo = 15.0, hi = 35.0
            let x = geo.size.width * CGFloat((min(max(bmi, lo), hi) - lo) / (hi - lo))
            ZStack(alignment: .topLeading) {
                HStack(spacing: 3) {
                    ForEach(bands, id: \.0) { category, range in
                        Capsule()
                            .fill(category.color.gradient)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                            .frame(width: max(0, geo.size.width * CGFloat((range.upperBound - range.lowerBound) / (hi - lo)) - 3))
                    }
                }
                .frame(height: 10)
                .padding(.top, Space.l)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.caption)
                    .shadow(radius: 2)
                    .offset(x: x - 6)
            }
        }
    }
}
