import SwiftUI

/// "How hard was that?" after a session: Easy, Just right or Hard (stored as RPE 3, 5 or 7 on each
/// exercise family practised), or "Something hurt", which swaps that exercise for its easier level
/// for a week and shows the safety advice. Never a diagnosis.
struct EffortCard: View {
    @EnvironmentObject private var model: AppModel
    /// The families the session trained, and what logging them already changed (a break, a step down).
    let results: [FamilyResult]
    let changes: [String: Progression.Change]

    @State private var effort: Effort?
    @State private var pickingHurt = false
    @State private var hurt: Set<String> = []
    @State private var answered = false
    @State private var outcome: [String: Progression.Change] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("How hard was that?", feature: .plan)
            if let note = loggingNote {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
            }
            if answered {
                Label(message, systemImage: hurt.isEmpty ? "checkmark.circle.fill" : "cross.case.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Feature.plan.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !hurt.isEmpty {
                    Text("Stop any move that causes sharp pain. If pain is sharp, doesn't settle, or comes with chest pain or dizziness, stop and talk to a doctor or physiotherapist.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if pickingHurt {
                Text("Which one hurt?").font(.subheadline.weight(.semibold))
                ForEach(results, id: \.family) { result in
                    let picked = hurt.contains(result.family)
                    Button {
                        if picked { hurt.remove(result.family) } else { hurt.insert(result.family) }
                    } label: {
                        Label(name(result.family, level: result.level), systemImage: picked ? "checkmark.circle.fill" : "circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(picked ? AnyShapeStyle(Feature.plan.ink) : AnyShapeStyle(Color.primary))
                }
                HStack(spacing: Space.m) {
                    Button("Back") { pickingHurt = false; hurt = [] }
                        .buttonStyle(.bordered)
                    Button("Done") { submit(nil) }
                        .buttonStyle(.borderedProminent)
                        .disabled(hurt.isEmpty)
                }
            } else {
                // Three answers side by side, or stacked at accessibility sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.s) { effortButtons }
                    VStack(spacing: Space.s) { effortButtons }
                }
                Button {
                    pickingHurt = true
                } label: {
                    Label("Something hurt", systemImage: "bandage.fill").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedCard(.plan)
        .animation(.snappy, value: answered)
        .animation(.snappy, value: pickingHurt)
    }

    @ViewBuilder
    private var effortButtons: some View {
        ForEach(Effort.allCases) { effort in
            Button { submit(effort) } label: {
                VStack(spacing: Space.xs) {
                    Image(systemName: effort.symbol).font(.title3)
                    Text(effort.label).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.m)
                .background(Feature.plan.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Feature.plan.ink)
        }
    }

    private func submit(_ effort: Effort?) {
        self.effort = effort
        outcome = model.rateSession(effort, hurt: hurt, families: results.map(\.family))
        answered = true
    }

    private func name(_ family: String, level: Int) -> String {
        ExerciseLibrary.shared.family(family)?.exercise(at: level).name ?? family
    }

    private func names(_ families: [String], level: (String) -> Int) -> String {
        families.map { name($0, level: level($0)) }.formatted(.list(type: .and))
    }

    /// What logging the session changed before the question: easing back in, or a step down.
    private var loggingNote: String? {
        let eased = results.filter { changes[$0.family] == .easeBack }.map(\.family)
        let down = results.filter { changes[$0.family] == .down }.map(\.family)
        let level = { (id: String) in model.progress(for: id)?.level ?? 0 }
        if !down.isEmpty { return String(localized: "\(names(down, level: level)) is a step easier next time, so every rep counts.") }
        if !eased.isEmpty { return String(localized: "Welcome back. We eased you in one level lower after the break.") }
        return nil
    }

    private var message: String {
        let level = { (id: String) in model.progress(for: id)?.level ?? 0 }
        if !hurt.isEmpty {
            return String(localized: "Sorry that hurt. \(names(Array(hurt), level: { max(level($0) - 1, 0) })) will be the easier version for a week.")
        }
        let up = results.map(\.family).filter { outcome[$0] == .up }
        if !up.isEmpty { return String(localized: "Level up! Next time: \(names(up, level: level)).") }
        switch effort {
        case .easy: return String(localized: "Nice. One more easy session and we go up.")
        case .hard:
            let dropping = results.contains { Progression.dropsASet(model.progress(for: $0.family)) }
            return dropping ? String(localized: "Two hard sessions in a row: same level, one set fewer next time.")
                            : String(localized: "Thanks. We'll stay at this level until it feels easier.")
        default: return String(localized: "Good. That's the right level for now.")
        }
    }
}
