import Charts
import SwiftUI

/// Everyday tracking: steps, food calories and BMI. Everything stays on the phone.
struct TrackView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var steps: StepCounter

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink { StepsView() } label: { stepsCard }
                    NavigationLink { FoodLogView() } label: { caloriesCard }
                    NavigationLink { BMIView() } label: { bmiCard }
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

    private var stepsCard: some View {
        HStack(spacing: 16) {
            ProgressRing(progress: steps.progress, color: .accentColor) {
                Image(systemName: "figure.walk").font(.title2.bold()).foregroundStyle(Color.accentColor)
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("Steps").font(.subheadline).foregroundStyle(.secondary)
                switch steps.status {
                case .unavailable:
                    Text("Not available on this device").font(.headline)
                case .denied:
                    Text("Allow Motion & Fitness").font(.headline)
                    Text("iPhone Settings › Privacy & Security").font(.caption).foregroundStyle(.secondary)
                default:
                    Text(steps.today.formatted()).font(.system(.title, design: .rounded, weight: .bold))
                    Text("of \(steps.goal.formatted()) · \(Steps.kilometres(steps.today), specifier: "%.1f") km")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            WeekBars(days: steps.week, goal: steps.goal)
                .frame(width: 88, height: 48)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .card()
    }

    private var caloriesCard: some View {
        let eaten = model.caloriesEaten()
        let target = model.profile?.calorieTarget
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Calories", systemImage: "fork.knife").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(eaten.formatted()).font(.system(.title, design: .rounded, weight: .bold))
                Text("kcal eaten today").foregroundStyle(.secondary)
                Spacer()
                if let target {
                    let left = target - eaten
                    Text(left >= 0 ? "\(left.formatted()) left" : "\((-left).formatted()) over")
                        .font(.headline)
                        .foregroundStyle(left >= 0 ? Color.green : Color.orange)
                }
            }
            if let target {
                ProgressView(value: min(Double(eaten), Double(target)), total: Double(target))
                    .tint(eaten > target ? .orange : .accentColor)
                Text("Daily target about \(target.formatted()) kcal").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Add your height and weight under BMI to get a daily target.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var bmiCard: some View {
        HStack(spacing: 16) {
            if let bmi = model.profile?.bmi {
                let category = BMI.category(bmi)
                VStack(alignment: .leading, spacing: 4) {
                    Text("BMI").font(.subheadline).foregroundStyle(.secondary)
                    Text(bmi, format: .number.precision(.fractionLength(1)))
                        .font(.system(.title, design: .rounded, weight: .bold))
                }
                Text(category.label)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(category.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(category.color)
            } else {
                Image(systemName: "scalemass.fill").font(.title).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BMI calculator").font(.headline)
                    Text("Enter your height and weight").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .card()
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

    var body: some View {
        Chart(days) { day in
            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.steps))
                .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Color.accentColor : Color.accentColor.opacity(day.steps >= goal ? 0.6 : 0.3))
                .clipShape(Capsule())
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

// MARK: - Steps

struct StepsView: View {
    @EnvironmentObject private var steps: StepCounter

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    ProgressRing(progress: steps.progress, color: .accentColor, lineWidth: 16) {
                        VStack(spacing: 2) {
                            Text(steps.today.formatted()).font(.system(size: 40, weight: .bold, design: .rounded))
                            Text("steps today").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 210, height: 210)
                    HStack(spacing: 28) {
                        stat("\(Steps.kilometres(steps.today).formatted(.number.precision(.fractionLength(1)))) km", "distance")
                        stat("\(max(steps.goal - steps.today, 0).formatted())", "to your goal")
                        stat("\(Int(Double(steps.today) * 0.04).formatted())", "kcal burned")
                    }
                }
                .frame(maxWidth: .infinity)
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Last 7 days").font(.headline)
                    Chart {
                        ForEach(steps.week) { day in
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.steps))
                                .foregroundStyle(day.steps >= steps.goal ? Color.green.gradient : Color.accentColor.gradient)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
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
                .card()

                VStack(alignment: .leading, spacing: 10) {
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
                .card()
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle("Steps")
        .onAppear { steps.start() }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Food

struct FoodLogView: View {
    @EnvironmentObject private var model: AppModel
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var adding = false
    @State private var snapping = false

    var body: some View {
        let entries = model.foods(on: day)
        let eaten = model.caloriesEaten(on: day)
        let target = model.profile?.calorieTarget
        List {
            Section {
                HStack(spacing: 18) {
                    ProgressRing(progress: target.map { min(Double(eaten) / Double($0), 1) } ?? 0,
                                 color: target.map { eaten > $0 ? Color.orange : Color.accentColor } ?? .accentColor, lineWidth: 12) {
                        VStack(spacing: 0) {
                            Text(eaten.formatted()).font(.system(.title2, design: .rounded, weight: .bold))
                            Text("kcal").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 110, height: 110)
                    VStack(alignment: .leading, spacing: 6) {
                        if let target {
                            Text("Target \(target.formatted()) kcal").font(.headline)
                            let left = target - eaten
                            Text(left >= 0 ? "\(left.formatted()) kcal left" : "\((-left).formatted()) kcal over")
                                .foregroundStyle(left >= 0 ? Color.green : Color.orange)
                        } else {
                            Text("No daily target yet").font(.headline)
                            NavigationLink("Add height and weight") { BMIView() }
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 6)
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
                            Text(entry.name)
                            Text(servingsLabel(entry)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(entry.total) kcal").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    offsets.map { entries[$0].id }.forEach(model.removeFood)
                }
                Button { snapping = true } label: {
                    Label("Snap your plate", systemImage: "camera.fill").font(.headline)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Snap your plate", systemImage: "camera") { snapping = true }
            }
        }
    }

    private var dayTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    private func shift(_ days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: day), next <= Date() { day = next }
    }

    private func servingsLabel(_ entry: FoodEntry) -> String {
        let count = entry.servings == entry.servings.rounded() ? "\(Int(entry.servings))" : String(format: "%.1f", entry.servings)
        return "\(count) × \(entry.kcal) kcal"
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
                    Section("Add \(picked.name)") {
                        Stepper("Servings: \(servings.formatted()) × \(picked.serving)", value: $servings, in: 0.5...10, step: 0.5)
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
                                    Text(item.name).foregroundStyle(Color.primary)
                                    Text(item.serving).font(.caption).foregroundStyle(.secondary)
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

    var body: some View {
        let height = metricHeight ? heightCm : BMI.centimetres(feet: feet, inches: inches)
        let bmi = BMI.value(weightKg: weightKg, heightCm: height) ?? 0
        let category = BMI.category(bmi)
        Form {
            Section {
                VStack(spacing: 14) {
                    Text(bmi, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(category.label)
                        .font(.headline)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(category.color.opacity(0.18), in: Capsule())
                        .foregroundStyle(category.color)
                    BMIGauge(bmi: bmi)
                        .frame(height: 34)
                    Text(category.message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    let range = BMI.healthyWeight(heightCm: height)
                    Text("A healthy weight for your height is about \(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded())) kg.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .animation(.snappy, value: bmi)
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
                Stepper("\(weightKg, specifier: "%.1f") kg", value: $weightKg, in: 30...200, step: 0.5)
                Slider(value: $weightKg, in: 30...150, step: 0.5)
            }

            Section {
                let saved = isSaved(height: height)
                Button(saved ? "Saved to your profile" : "Save to my profile") {
                    model.updateBody(heightCm: height, weightKg: weightKg)
                }
                .font(.headline)
                .disabled(saved)
            } footer: {
                Text("Uses the BMI cut-offs recommended for South Asians (healthy 18.5–22.9), since health risks rise at a lower BMI than the international ranges suggest. BMI doesn't account for muscle, so treat it as a rough guide, not a diagnosis.")
            }

            if model.weights.count >= 2 {
                Section("Weight over time") {
                    Chart(model.weights, id: \.date) { entry in
                        LineMark(x: .value("Date", entry.date), y: .value("kg", entry.kg))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", entry.date), y: .value("kg", entry.kg))
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
    private let bands: [(BMI.Category, ClosedRange<Double>)] = [
        (.underweight, 15...18.5), (.healthy, 18.5...23), (.overweight, 23...25), (.obese, 25...35),
    ]

    var body: some View {
        GeometryReader { geo in
            let lo = 15.0, hi = 35.0
            let x = geo.size.width * CGFloat((min(max(bmi, lo), hi) - lo) / (hi - lo))
            ZStack(alignment: .topLeading) {
                HStack(spacing: 3) {
                    ForEach(bands, id: \.0) { category, range in
                        Capsule()
                            .fill(category.color.opacity(0.75))
                            .frame(width: max(0, geo.size.width * CGFloat((range.upperBound - range.lowerBound) / (hi - lo)) - 3))
                    }
                }
                .frame(height: 10)
                .padding(.top, 14)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.caption)
                    .offset(x: x - 6)
            }
        }
    }
}
