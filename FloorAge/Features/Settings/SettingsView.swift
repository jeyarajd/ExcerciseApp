import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach
    @EnvironmentObject private var store: Store
    @State private var confirmingReset = false
    @State private var showingPlus = false
    @State private var showingFamily = false
    @State private var coachStyle = CoachStyle.current
    @State private var healthWorkouts = AppleHealth.savesWorkouts
    @State private var healthSteps = AppleHealth.readsSteps
    @EnvironmentObject private var steps: StepCounter
    @State private var storeMessage: String?
    @State private var reminderOn = Reminders.isOn
    @State private var reminderTime = ReminderTime.date(fromMinute: Reminders.minuteOfDay)
    @State private var notificationsDenied = false
    @AppStorage("pelvicFloor") private var pelvicFloor = true

    var body: some View {
        NavigationStack {
            Form {
                plusSection

                Section {
                    Button { showingFamily = true } label: {
                        HStack(spacing: 12) {
                            MemberAvatar(member: model.activeMember, size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Family").font(.headline)
                                Text(model.members.count == 1 ? String(localized: "Just you so far") : String(localized: "\(model.members.count) people on this iPhone"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }

                Section {
                    Picker("Coach", selection: Binding(get: { coachStyle }, set: { CoachStyle.current = $0; coachStyle = $0 })) {
                        ForEach(CoachStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: coachStyle)
                } header: {
                    Text("Coach look")
                } footer: {
                    Text("Your coach is a woman or a man to match your profile.")
                }

                Section("Voice coach") {
                    Toggle("Spoken coaching", isOn: $voice.enabled)
                    if VoiceCoach.appLanguage == "en" {
                        Picker("Accent", selection: $voice.accent) {
                            ForEach(VoiceCoach.accents) { accent in
                                Text(accent.label).tag(accent.code)
                            }
                        }
                    } else {
                        LabeledContent("Voice", value: Locale.current.localizedString(forIdentifier: voice.voiceLanguage) ?? voice.voiceLanguage)
                    }
                    Button("Test voice") {
                        voice.say(String(localized: "Hello! Let's get moving today."), interrupt: true)
                    }
                    Text("For a more natural voice, download an Enhanced or Premium voice in iPhone Settings › Accessibility › Spoken Content › Voices.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if store.hasPlus {
                        Toggle("Pelvic floor (Kegel) exercises", isOn: $pelvicFloor)
                    } else {
                        Button { showingPlus = true } label: {
                            HStack {
                                Text("Pelvic floor (Kegel) exercises")
                                Spacer()
                                PlusBadge()
                            }
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("Daily session")
                } footer: {
                    Text("Adds about a minute of guided pelvic floor squeezes to the end of each session. Good for bladder control, core support and recovery, for women and men.")
                }

                Section {
                    Toggle("Evening reminder", isOn: $reminderOn)
                        .onChange(of: reminderOn) { _, on in
                            guard on != Reminders.isOn else { return }
                            Task {
                                if on {
                                    let granted = await Reminders.enable()
                                    notificationsDenied = !granted
                                    if granted { await model.refreshReminders() } else { reminderOn = false }
                                } else {
                                    await Reminders.disable()
                                }
                            }
                        }
                    if reminderOn {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .onChange(of: reminderTime) { _, time in
                                Reminders.minuteOfDay = ReminderTime.minute(of: time)
                                Task { await model.refreshReminders() }
                            }
                    }
                } header: {
                    Text("Reminder")
                } footer: {
                    Text(notificationsDenied
                         ? "Notifications are off for Floor Age. Turn them on in iPhone Settings › Notifications."
                         : "One reminder a day, only if you haven't done today's training yet. None on rest days.")
                }

                if AppleHealth.isAvailable, model.isOwner {
                    Section {
                        Toggle("Save workouts to Apple Health", isOn: $healthWorkouts)
                            .onChange(of: healthWorkouts) { _, on in
                                AppleHealth.savesWorkouts = on
                                if on { Task { _ = await AppleHealth.requestWorkoutAccess() } }
                            }
                        Toggle("Read steps from Apple Health", isOn: $healthSteps)
                            .onChange(of: healthSteps) { _, on in
                                Task {
                                    if on { _ = await AppleHealth.requestStepAccess() }
                                    AppleHealth.readsSteps = on
                                    steps.start()
                                }
                            }
                    } header: {
                        Text("Apple Health")
                    } footer: {
                        Text("Sessions and run/walk days count towards your Activity rings. Reading steps from Health adds the steps your Apple Watch counts. Floor Age only shares with Health on this iPhone.")
                    }
                }

                if let profile = model.profile {
                    Section("Profile") {
                        NavigationLink {
                            ProfileEditView(profile: profile)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name.isEmpty ? "Age \(profile.age)" : "\(profile.name), \(profile.age)")
                                Text(profile.limitations.isEmpty
                                     ? String(localized: "No limitations")
                                     : String(localized: "Adapted for \(profile.limitations.map(\.shortLabel).sorted().joined(separator: ", "))"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Delete all my data", role: .destructive) { confirmingReset = true }
                } footer: {
                    Text("Your data is stored only on this iPhone. Floor Age is a fitness estimate, not medical advice.")
                }
            }
            .appBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPlus) {
                PlusView().environmentObject(store)
            }
            .sheet(isPresented: $showingFamily) {
                FamilyView().environmentObject(model).environmentObject(store)
            }
            .messageAlert($storeMessage)
            .confirmationDialog("Delete your profile, Floor Age results and session history?",
                                isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    model.resetAll()
                    reminderOn = false
                    Task { await Reminders.disable() }
                }
            }
        }
    }
}

extension SettingsView {
    /// Plus status, the way to buy it, and Restore Purchases (which App Review requires).
    fileprivate var plusSection: some View {
        Section {
            if store.hasPlus {
                HStack(spacing: 12) {
                    FeatureBadge(feature: .plus, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Floor Age Plus").font(.headline)
                        Text("Unlocked. Thank you!").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Button { showingPlus = true } label: {
                    HStack(spacing: 12) {
                        FeatureBadge(feature: .plus, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Floor Age Plus").font(.headline)
                            Text("Training plan, family profiles, food photos, sleep, pelvic floor and progress history")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let price = store.price {
                            Text(price).font(.subheadline.weight(.semibold)).foregroundStyle(Feature.plus.tint)
                        }
                    }
                }
                .tint(.primary)
                Button("Restore Purchases") {
                    Task { storeMessage = await store.restore() }
                }
                .disabled(store.busy)
            }
        } footer: {
            if !store.hasPlus {
                Text("One purchase unlocks Plus for good. No subscription.")
            }
        }
    }
}

enum ReminderTime {
    /// "6:00 PM", the current reminder time.
    static var label: String { date(fromMinute: Reminders.minuteOfDay).formatted(date: .omitted, time: .shortened) }

    static func date(fromMinute minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }

    static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
    }
}

/// Change name, age or limitations after onboarding. Age feeds the Floor Age comparison and
/// limitations drive `PlanBuilder.unsafe`, so both matter.
struct ProfileEditView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var age: Int
    @State private var limitations: Set<Limitation>
    @State private var gender: Gender?

    init(profile: Profile) {
        _name = State(initialValue: profile.name)
        _age = State(initialValue: profile.age)
        _limitations = State(initialValue: profile.limitations)
        _gender = State(initialValue: profile.gender)
    }

    var body: some View {
        Form {
            Section {
                TextField("First name (optional)", text: $name)
                    .textContentType(.givenName)
                Stepper("Age: \(age)", value: $age, in: 18...95)
                GenderPicker(gender: $gender)
            } footer: {
                Text("Your coach matches you. Past Floor Age checks keep the age you had when you took them.")
            }
            Section {
                ForEach(Limitation.allCases) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { limitations.contains(item) },
                        set: { on in
                            if on { limitations.insert(item) } else { limitations.remove(item) }
                        }
                    ))
                }
            } header: {
                Text("Anything we should know?")
            } footer: {
                Text("Moves that could hurt are skipped or made gentler.")
            }
        }
        .appBackground()
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    model.profile = Profile(name: name.trimmingCharacters(in: .whitespaces), age: age,
                                            limitations: limitations, gender: gender)
                    dismiss()
                }
            }
        }
    }
}

/// "I am a woman / man / prefer not to say". Picks which coach demonstrates.
struct GenderPicker: View {
    @Binding var gender: Gender?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("I am").font(.subheadline).foregroundStyle(.secondary)
            Picker("I am", selection: $gender) {
                ForEach(Gender.allCases) { Text($0.label).tag(Gender?.some($0)) }
                Text("Prefer not to say").tag(Gender?.none)
            }
            .pickerStyle(.segmented)
        }
    }
}
