import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach
    @StateObject private var avatar = AvatarController(exerciseID: "arm_raise")

    @State private var page = 0
    @State private var name = ""
    @State private var age = 40
    @State private var gender: Gender?
    @State private var limitations: Set<Limitation> = []

    var body: some View {
        VStack(spacing: 0) {
            AvatarView(controller: avatar)
                .frame(maxHeight: page == 0 ? .infinity : 240)
                .animation(.easeInOut, value: page)
            Group {
                switch page {
                case 0: welcome
                case 1: aboutYou
                default: safety
                }
            }
            .padding()
        }
        .background(AppBackground())
        .onAppear {
            voice.say("\(Region.greeting) I'm your coach. Let's find out how old your body moves, and make it younger.")
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How old does your body move?")
                .font(.largeTitle.bold())
            Text("Find your Floor Age with 4 simple tests, then train with a coach who shows every move and talks you through it.")
                .foregroundStyle(.secondary)
            primaryButton("Get started") { page = 1 }
        }
    }

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About you").font(.title.bold())
            TextField("First name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)
                .textContentType(.givenName)
            Stepper("Age: \(age)", value: $age, in: 18...95)
                .font(.headline)
            GenderPicker(gender: $gender)
                .onChange(of: gender) { _, value in CoachLook.preview(value) }
            Text("Your age is used to compare your Floor Age, and your coach matches you. It all stays on this phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            primaryButton("Next") {
                avatar.play(id: "idle")
                page = 2
            }
        }
    }

    private var safety: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
                        gender: gender
                    )
                }
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.top, 8)
    }
}
