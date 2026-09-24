import SwiftUI

/// The 30-day challenge on Today: an invitation, today's progress, or the final tally.
struct ChallengeCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let challenge = model.challenge {
            NavigationLink { ChallengeView() } label: { progress(challenge) }
                .buttonStyle(.plain)
        } else {
            invitation
        }
    }

    private var invitation: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("30-day challenge").font(.caption.weight(.heavy)).tracking(1.6).textCase(.uppercase).opacity(0.9)
            Text("Get off the floor").font(.display(.title2))
            Text("Train on 30 days, any session counts, and collect 5 badges along the way.")
                .font(.subheadline)
                .opacity(0.9)
            HStack(spacing: Space.s) {
                ForEach(Challenge.Badge.allCases) { badge in
                    Image(systemName: badge.symbol)
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.22), in: Circle())
                }
            }
            Button {
                model.startChallenge()
            } label: {
                Label("Start the challenge", systemImage: "flag.checkered")
            }
            .buttonStyle(OnHeroButtonStyle(feature: .challenge))
            .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroCard(.challenge)
    }

    private func progress(_ challenge: Challenge) -> some View {
        let over = challenge.isOver()
        return HStack(spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(over ? "Challenge complete" : "Day \(challenge.dayNumber()) of \(Challenge.length)")
                    .font(.caption.weight(.heavy)).tracking(1.4).textCase(.uppercase).opacity(0.9)
                Text("Get off the floor").font(.display(.title3))
                if let next = challenge.nextBadge, !over {
                    Label("\(next.rawValue - challenge.completed) more to “\(next.title)”", systemImage: next.symbol)
                        .font(.caption.weight(.semibold))
                } else {
                    Label("\(challenge.earned.count) of \(Challenge.Badge.allCases.count) badges", systemImage: "trophy.fill")
                        .font(.caption.weight(.semibold))
                }
                DayDots(challenge: challenge, size: 7)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            ArcGauge(progress: Double(challenge.completed) / Double(Challenge.length), lineWidth: 9) {
                VStack(spacing: -2) {
                    Text("\(challenge.completed)").font(.metric(22))
                    Text("days").font(.caption2).opacity(0.85)
                }
            }
            .frame(width: 92)
        }
        .heroCard(.challenge)
    }
}

/// Thirty small dots, filled for days trained.
private struct DayDots: View {
    let challenge: Challenge
    var size: CGFloat

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(size), spacing: size * 0.6), count: 15)
        LazyVGrid(columns: columns, alignment: .leading, spacing: size * 0.6) {
            ForEach(challenge.days, id: \.self) { day in
                Circle()
                    .fill(challenge.trained(day) ? .white : .white.opacity(0.28))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The challenge calendar and badges.
struct ChallengeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmingEnd = false

    var body: some View {
        ScrollView {
            if let challenge = model.challenge {
                VStack(spacing: Space.l) {
                    header(challenge)
                    calendar(challenge)
                    badges(challenge)
                    Button(challenge.isOver() ? "Start a new challenge" : "End the challenge") {
                        if challenge.isOver() { model.startChallenge() } else { confirmingEnd = true }
                    }
                    .font(.headline)
                    .foregroundStyle(challenge.isOver() ? Feature.challenge.colors[1] : .secondary)
                    .padding(.top, Space.xs)
                }
                .padding()
            }
        }
        .background(AppBackground())
        .navigationTitle("30-day challenge")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("End the challenge? Your badges so far are kept on this screen until you start a new one.",
                            isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End the challenge", role: .destructive) { model.endChallenge() }
        }
    }

    private func header(_ challenge: Challenge) -> some View {
        VStack(spacing: Space.s) {
            Image(systemName: "trophy.fill").font(.system(size: 40)).shadow(color: .white.opacity(0.5), radius: 10)
            Text("Get off the floor").font(.display(.title))
            Text(challenge.isOver()
                 ? "You trained on \(challenge.completed) of \(Challenge.length) days."
                 : "Day \(challenge.dayNumber()) of \(Challenge.length) · \(challenge.completed) trained")
                .font(.subheadline.weight(.semibold))
                .opacity(0.9)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s)
        .heroCard(.challenge, padding: Space.xl)
    }

    private func calendar(_ challenge: Challenge) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 6)
        let today = Calendar.current.startOfDay(for: Date())
        return VStack(alignment: .leading, spacing: Space.m) {
            Text("Your 30 days").font(.display(.headline))
            LazyVGrid(columns: columns, spacing: Space.s) {
                ForEach(Array(challenge.days.enumerated()), id: \.offset) { index, day in
                    let done = challenge.trained(day)
                    let isMilestone = Challenge.Badge(rawValue: index + 1) != nil
                    VStack(spacing: 2) {
                        if done {
                            Image(systemName: "checkmark").font(.caption.weight(.heavy))
                        } else {
                            Text("\(index + 1)").font(.caption.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(done ? .white : day > today ? Color.secondary.opacity(0.6) : .secondary)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .fill(done ? AnyShapeStyle(Feature.challenge.gradient) : AnyShapeStyle(Color(.systemBackground).opacity(0.7)))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(day == today ? Feature.challenge.colors[1] : isMilestone ? Feature.challenge.tint.opacity(0.6) : .clear,
                                          lineWidth: day == today ? 2 : 1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(day.formatted(date: .abbreviated, time: .omitted)))
                    .accessibilityValue(done ? Text("Trained") : Text("Not yet"))
                }
            }
            Text("Any session counts: the daily session, pelvic floor or a plan day. Missing a day never takes a badge away.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .tintedCard(.challenge)
    }

    private func badges(_ challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Badges").font(.display(.headline))
            ForEach(Challenge.Badge.allCases) { badge in
                let earned = challenge.earned.contains(badge)
                HStack(spacing: Space.l) {
                    BadgeMedal(badge: badge, earned: earned, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge.title).font(.headline)
                        Text(badge.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if earned {
                        Image(systemName: "checkmark.seal.fill").font(.title3).foregroundStyle(Feature.challenge.gradient)
                    } else {
                        Text("\(max(badge.rawValue - challenge.completed, 0)) to go")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(earned ? 1 : 0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedCard(.challenge)
    }
}

/// A round medal for a badge: gold when earned, grey with a lock until then.
struct BadgeMedal: View {
    let badge: Challenge.Badge
    let earned: Bool
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(earned ? AnyShapeStyle(Feature.challenge.gradient) : AnyShapeStyle(Color.secondary.opacity(0.18)))
            Circle()
                .strokeBorder(.white.opacity(earned ? 0.7 : 0.3), lineWidth: size * 0.05)
                .padding(size * 0.08)
            Image(systemName: earned ? badge.symbol : "lock.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(earned ? .white : .secondary)
        }
        .frame(width: size, height: size)
        .shadow(color: earned ? Feature.challenge.colors[1].opacity(0.4) : .clear, radius: size * 0.15, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

/// Shown over the app when a badge is earned: the medal, a little confetti, and on we go.
struct BadgeCelebration: View {
    let badge: Challenge.Badge
    let onDone: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture(perform: onDone)
            ConfettiView(colors: Feature.challenge.colors + [.white, Feature.plan.tint, Feature.calories.tint])
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: Space.l) {
                BadgeMedal(badge: badge, earned: true, size: 120)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.4)
                    .rotationEffect(.degrees(shown || reduceMotion ? 0 : -30))
                Text("New badge").font(.caption.weight(.heavy)).tracking(2).textCase(.uppercase).foregroundStyle(Feature.challenge.inkColors[1])
                Text(badge.title).font(.display(.largeTitle)).multilineTextAlignment(.center)
                Text(badge.detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Keep going", action: onDone)
                    .buttonStyle(GradientButtonStyle(feature: .challenge))
                    .padding(.top, Space.s)
            }
            .padding(Space.xl)
            .frame(maxWidth: 340)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
            .padding()
            .scaleEffect(shown ? 1 : 0.9)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0.45)) { shown = true }
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// Falling confetti for a few seconds.
struct ConfettiView: View {
    let colors: [Color]
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let pieces: [Piece] = (0..<90).map { _ in Piece() }

    private struct Piece {
        let x = Double.random(in: 0...1)
        let delay = Double.random(in: 0...0.8)
        let speed = Double.random(in: 0.25...0.45)
        let sway = Double.random(in: 0.02...0.06)
        let spin = Double.random(in: 2...7)
        let size = Double.random(in: 6...11)
        let colorIndex = Int.random(in: 0..<100)
        let round = Bool.random()
    }

    var body: some View {
        // Decorative, so none at all with Reduce Motion.
        if !reduceMotion { confetti }
    }

    private var confetti: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                for piece in pieces {
                    let life = t - piece.delay
                    guard life > 0 else { continue }
                    let y = -0.05 + life * piece.speed
                    guard y < 1.1 else { continue }
                    let x = piece.x + sin(life * piece.spin) * piece.sway
                    let fade = max(0, min(1, (4.5 - t) / 1))
                    var ctx = context
                    ctx.opacity = fade
                    ctx.translateBy(x: x * size.width, y: y * size.height)
                    ctx.rotate(by: .radians(life * piece.spin))
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / (piece.round ? 1 : 2))
                    let shape = piece.round ? Path(ellipseIn: rect) : Path(rect)
                    ctx.fill(shape, with: .color(colors[piece.colorIndex % colors.count]))
                }
            }
        }
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }
}
