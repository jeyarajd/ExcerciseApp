import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach
    @StateObject private var avatar = AvatarController(exerciseID: "arm_raise")

    @State private var page: Int
    @State private var name = ""
    @State private var age = 40
    @State private var gender: Gender?
    @State private var coach = CoachLook.current
    @State private var limitations: Set<Limitation> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `startPage` 2 opens on the coach choice (screenshots).
    init(startPage: Int = 0) {
        _page = State(initialValue: startPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            AvatarView(controller: avatar)
                .frame(maxHeight: page == 0 || page == 2 ? .infinity : 240)
                .animation(.easeInOut, value: page)
            Group {
                switch page {
                case 0: welcome
                case 1: aboutYou
                case 2: coachChoice
                default: safety
                }
            }
            .padding()
        }
        .background(AppBackground())
        .overlay(alignment: .topLeading) {
            if model.canCancelNewMember {
                Button("Cancel") { model.cancelNewMember() }
                    .font(.headline)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
        .onAppear {
            if page == 2 {
                avatar.play(id: "idle")
                avatar.turnsSlowly = !reduceMotion
                return
            }
            voice.say(String(localized: "\(Region.greeting) I'm your coach. Let's find out how old your body moves, and make it younger."))
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if model.isOwner {
                Text("How old does your body move?")
                    .font(.display(.largeTitle))
                Text("Find your Floor Age with 4 simple tests, then train with a coach who shows every move and talks you through it.")
                    .foregroundStyle(.secondary)
            } else {
                Eyebrow("Family", feature: .plus)
                Text("Add a family member")
                    .font(.display(.largeTitle))
                Text("They get their own Floor Age, plan and history on this iPhone. Hand them the phone, or fill it in together.")
                    .foregroundStyle(.secondary)
            }
            primaryButton("Get started") { page = 1 }
        }
    }

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("About you").font(.title.bold())
            TextField("First name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)
                .textContentType(.givenName)
            Stepper("Age: \(age)", value: $age, in: 18...95)
                .font(.headline)
            GenderPicker(gender: $gender)
                .onChange(of: gender) { _, value in coach = CoachLook(matching: value) }
            Text("Your age is used to compare your Floor Age. It all stays on this phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            primaryButton("Next") {
                avatar.play(id: "idle")
                avatar.turnsSlowly = !reduceMotion
                page = 2
                sayHello()
            }
        }
        .onChange(of: coach) { _, value in CoachLook.preview(value) }
    }

    /// Who coaches you and how they look, with the coach turning slowly above and saying hello.
    private var coachChoice: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Choose your coach").font(.title.bold()).fixedSize(horizontal: false, vertical: true)
            Picker("Coach", selection: $coach) {
                ForEach(CoachLook.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("You can change your coach at any time in Settings.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            primaryButton("Next") {
                avatar.turnsSlowly = false
                page = 3
            }
        }
        .sensoryFeedback(.selection, trigger: coach)
        .onChange(of: coach) { _, value in
            CoachLook.preview(value)
            sayHello()
        }
    }

    private func sayHello() {
        voice.say(String(localized: "Hi! I'm your coach. I'll show you every move and count with you."), interrupt: true)
    }

    private var safety: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Anything we should know?").font(.title.bold())
                Text("We'll skip or adapt moves that could hurt. Select all that apply.")
                    .foregroundStyle(.secondary)
                ForEach(Limitation.allCases) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { limitations.contains(item) },
                        set: { on in
                            if on { limitations.insert(item) } else { limitations.remove(item) }
                        }
                    ))
                }
                if limitations.contains(.medical) {
                    Label("Please check with your doctor before starting. We'll keep sessions gentle.", systemImage: "stethoscope")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Text("This app gives general fitness guidance, not medical advice. Stop if anything hurts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                primaryButton("Let's go") {
                    model.profile = Profile(
                        name: name.trimmingCharacters(in: .whitespaces),
                        age: age,
                        limitations: limitations,
                        gender: gender,
                        coach: coach
                    )
                }
            }
        }
    }

    private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.top, Space.s)
    }
}
