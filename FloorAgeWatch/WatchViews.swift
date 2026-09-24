import SwiftUI
import WatchKit

struct HomeView: View {
    @EnvironmentObject private var link: PhoneLink

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let session = link.session, !session.isDone {
                    NavigationLink { RemoteView() } label: { nowPlaying(session) }
                        .buttonStyle(.plain)
                }
                summary
                NavigationLink { ChairStandTestView() } label: {
                    testRow("30-Second Chair Stand", symbol: "chair.fill", gradient: WatchColors.chair)
                }
                .buttonStyle(.plain)
                NavigationLink { BalanceTestView() } label: {
                    testRow("One-Leg Balance", symbol: "figure.stand", gradient: WatchColors.balance)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Floor Age")
    }

    private var summary: some View {
        let snapshot = link.snapshot
        return VStack(alignment: .leading, spacing: 4) {
            Text("Floor Age").font(.caption2.weight(.heavy)).textCase(.uppercase).opacity(0.9)
            if let floorAge = snapshot?.floorAge {
                Text("\(floorAge)").font(.system(size: 40, weight: .heavy, design: .rounded))
                if let difference = snapshot?.difference {
                    Text(difference < 0 ? String(localized: "\(-difference) yrs younger") : difference > 0 ? String(localized: "\(difference) yrs older") : String(localized: "Right on your age"))
                        .font(.caption2.weight(.bold))
                }
            } else {
                Text("Take the check on your iPhone").font(.footnote.weight(.semibold))
            }
            HStack(spacing: 3) {
                ForEach(Array((snapshot?.week ?? Array(repeating: false, count: 7)).enumerated()), id: \.offset) { _, done in
                    Circle().fill(done ? .white : .white.opacity(0.3)).frame(width: 7, height: 7)
                }
            }
            if let snapshot {
                Label("\(snapshot.stepsToday.formatted()) steps", systemImage: "figure.walk").font(.caption2.weight(.semibold))
                if let day = snapshot.challengeDay {
                    Label("Challenge day \(day)", systemImage: "trophy.fill").font(.caption2.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(WatchColors.floorAge, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func nowPlaying(_ session: SessionStatus) -> some View {
        HStack {
            Image(systemName: session.isPaused ? "pause.circle.fill" : "play.circle.fill").font(.title3)
            VStack(alignment: .leading) {
                Text(session.exercise).font(.footnote.weight(.bold)).lineLimit(1)
                Text(session.detail).font(.caption2).opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func testRow(_ title: LocalizedStringKey, symbol: String, gradient: LinearGradient) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 30, height: 30)
                .background(gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title).font(.footnote.weight(.semibold)).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The guided session playing on the iPhone.
struct RemoteView: View {
    @EnvironmentObject private var link: PhoneLink

    var body: some View {
        if let session = link.session, !session.isDone {
            VStack(spacing: 6) {
                Text(session.step).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: session.progress)
                        .stroke(WatchColors.floorAge, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(session.exercise).font(.caption2.weight(.bold)).lineLimit(2).multilineTextAlignment(.center)
                        Text(session.detail).font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    .padding(10)
                }
                .frame(maxHeight: 110)
                HStack {
                    Button {
                        link.send(.pause)
                    } label: {
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    }
                    .accessibilityLabel(session.isPaused ? Text("Resume") : Text("Pause"))
                    Button {
                        link.send(.skip)
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .accessibilityLabel(Text("Next"))
                }
            }
            .navigationTitle(session.isResting ? Text("Rest") : Text("Session"))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "iphone").font(.title2)
                Text("Start a session on your iPhone to control it here.").font(.footnote).multilineTextAlignment(.center)
            }
        }
    }
}

/// The 30-second chair stand, counted from the wrist.
struct ChairStandTestView: View {
    @EnvironmentObject private var link: PhoneLink
    @StateObject private var sensor = WristMotionSensor()
    @State private var phase = Phase.ready
    @State private var countdown = 3
    @State private var remaining = 30
    @State private var stands = 0
    @State private var timer: Timer?

    enum Phase { case ready, countdown, running, done, sent }

    var body: some View {
        VStack(spacing: 8) {
            switch phase {
            case .ready:
                Text("Sit in the middle of a sturdy chair and cross your arms over your chest.")
                    .font(.footnote).multilineTextAlignment(.center)
                Button("Start") { begin() }.tint(WatchColors.accent)
            case .countdown:
                Text("\(countdown)").font(.system(size: 60, weight: .heavy, design: .rounded))
                Text("Get ready").font(.footnote)
            case .running:
                Text("\(sensor.stands)").font(.system(size: 56, weight: .heavy, design: .rounded)).contentTransition(.numericText())
                Text("stands · \(remaining) s").font(.footnote.weight(.semibold))
            case .done, .sent:
                Text("Full stands").font(.footnote)
                HStack {
                    Button { stands = max(0, stands - 1) } label: { Image(systemName: "minus") }
                    Text("\(stands)").font(.system(size: 36, weight: .heavy, design: .rounded)).frame(minWidth: 44)
                    Button { stands += 1 } label: { Image(systemName: "plus") }
                }
                Button(phase == .sent ? "Sent to iPhone" : "Send to iPhone") {
                    link.send(WatchTestResult(test: .chairStand, value: Double(stands)))
                    WKInterfaceDevice.current().play(.success)
                    phase = .sent
                }
                .tint(WatchColors.accent)
                .disabled(phase == .sent)
            }
        }
        .navigationTitle("Chair stand")
        .onDisappear {
            timer?.invalidate()
            sensor.stop()
        }
    }

    private func begin() {
        phase = .countdown
        countdown = 3
        WKInterfaceDevice.current().play(.start)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            switch phase {
            case .countdown:
                countdown -= 1
                WKInterfaceDevice.current().play(.click)
                if countdown == 0 {
                    phase = .running
                    remaining = 30
                    sensor.start()
                    WKInterfaceDevice.current().play(.start)
                }
            case .running:
                remaining -= 1
                if remaining == 15 { WKInterfaceDevice.current().play(.notification) }
                if remaining <= 0 {
                    t.invalidate()
                    sensor.stop()
                    stands = sensor.stands
                    phase = .done
                    WKInterfaceDevice.current().play(.stop)
                }
            default:
                t.invalidate()
            }
        }
    }
}

/// The one-leg balance timer: tap to start, tap the moment your foot touches down.
struct BalanceTestView: View {
    @EnvironmentObject private var link: PhoneLink
    @State private var start: Date?
    @State private var best: Double?
    @State private var sent = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let held = start.map { min(context.date.timeIntervalSince($0), 45) } ?? best ?? 0
            VStack(spacing: 8) {
                Text(String(format: "%.1f", held)).font(.system(size: 52, weight: .heavy, design: .rounded)).monospacedDigit()
                Text("seconds").font(.footnote)
                if start != nil {
                    Button("Stop") { stop() }.tint(.red)
                } else {
                    Button(best == nil ? "Start" : "Try again") {
                        start = Date()
                        sent = false
                        WKInterfaceDevice.current().play(.start)
                    }
                    .tint(WatchColors.accent)
                    if let best {
                        Button(sent ? "Sent to iPhone" : "Send to iPhone") {
                            link.send(WatchTestResult(test: .balance, value: best))
                            WKInterfaceDevice.current().play(.success)
                            sent = true
                        }
                        .disabled(sent)
                    }
                }
            }
            .onChange(of: Int(held)) { _, seconds in
                guard start != nil else { return }
                if seconds > 0, seconds % 10 == 0 { WKInterfaceDevice.current().play(.click) }
                if held >= 45 { stop() }
            }
        }
        .navigationTitle("Balance")
    }

    private func stop() {
        guard let start else { return }
        best = max(best ?? 0, min(Date().timeIntervalSince(start), 45))
        self.start = nil
        WKInterfaceDevice.current().play(.stop)
    }
}
