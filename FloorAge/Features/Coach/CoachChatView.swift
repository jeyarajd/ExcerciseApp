import SwiftUI

struct CoachChatView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach
    @StateObject private var avatar = AvatarController(exerciseID: "idle")

    @State private var messages: [CoachClient.Message] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @State private var speakReplies = true
    @FocusState private var inputFocused: Bool

    private let starters = [
        "I only have 10 minutes today",
        "I slept badly. Should I skip today?",
        "My knees hurt. What can I do instead?",
        "How do I improve my Floor Age?",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AvatarView(controller: avatar)
                    .frame(height: 170)
                    .overlay(alignment: .bottomTrailing) {
                        Toggle(isOn: $speakReplies) {
                            Image(systemName: speakReplies ? "speaker.wave.2.fill" : "speaker.slash")
                        }
                        .toggleStyle(.button)
                        .padding(8)
                        .accessibilityLabel("Speak replies")
                    }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if !CoachClient.isConfigured {
                                setupCard
                            }
                            if messages.isEmpty {
                                Text("Ask your coach anything about today's workout.")
                                    .foregroundStyle(.secondary)
                                ForEach(starters, id: \.self) { starter in
                                    Button(starter) { send(starter) }
                                        .buttonStyle(.bordered)
                                }
                            }
                            ForEach(messages) { message in
                                Bubble(message: message).id(message.id)
                            }
                            if sending {
                                ProgressView().padding(.leading, 8).id("typing")
                            }
                            if let error {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let id = messages.last?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
                inputBar
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Coach chat needs setup", systemImage: "wrench.and.screwdriver")
                .font(.headline)
            Text("Workouts and voice coaching work offline. Chat needs the coach server address in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message your coach", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { send(draft) }
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending else { return }
        draft = ""
        error = nil
        messages.append(.init(role: .user, content: trimmed))
        sending = true
        let history = messages
        let context = currentContext()
        Task {
            do {
                let reply = try await CoachClient().reply(to: history, context: context)
                messages.append(.init(role: .assistant, content: reply))
                if speakReplies { voice.say(reply, interrupt: true) }
            } catch {
                self.error = error.localizedDescription
            }
            sending = false
        }
    }

    private func currentContext() -> CoachClient.Context {
        let latest = model.latestResult
        return CoachClient.Context(
            age: model.profile?.age,
            floorAge: latest?.floorAge,
            weakestArea: latest?.weakest?.area,
            limitations: (model.profile?.limitations ?? []).map(\.rawValue).sorted(),
            sessionsThisWeek: model.lastSevenDays.filter { $0 }.count
        )
    }
}

private struct Bubble: View {
    let message: CoachClient.Message

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .padding(12)
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .background(isUser ? Color.accentColor : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
