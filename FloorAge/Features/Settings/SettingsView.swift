import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach
    @State private var serverURL = CoachClient.serverURL
    @State private var appToken = CoachClient.appToken
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Voice coach") {
                    Toggle("Spoken coaching", isOn: $voice.enabled)
                    Picker("Accent", selection: $voice.accent) {
                        ForEach(VoiceCoach.accents) { accent in
                            Text(accent.label).tag(accent.code)
                        }
                    }
                    Button("Test voice") {
                        voice.say("Hello! Let's get moving today.", interrupt: true)
                    }
                    Text("For a more natural voice, download an Enhanced or Premium voice in iPhone Settings › Accessibility › Spoken Content › Voices.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("https://your-coach-server.example.com", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: serverURL) { _, value in CoachClient.serverURL = value }
                    SecureField("App token (optional)", text: $appToken)
                        .onChange(of: appToken) { _, value in CoachClient.appToken = value }
                } header: {
                    Text("Coach chat server")
                } footer: {
                    Text("Chat messages go to this server, which asks Claude for a reply. Workouts work without it.")
                }

                if let profile = model.profile {
                    Section("Profile") {
                        LabeledContent("Age", value: "\(profile.age)")
                        if !profile.limitations.isEmpty {
                            LabeledContent("Adapted for", value: profile.limitations.map(\.rawValue).sorted().joined(separator: ", "))
                        }
                    }
                }

                Section {
                    Button("Delete all my data", role: .destructive) { confirmingReset = true }
                } footer: {
                    Text("Your data is stored only on this iPhone. Floor Age is a fitness estimate, not medical advice.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete your profile, Floor Age results and session history?",
                                isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { model.resetAll() }
            }
        }
    }
}
