import SwiftUI

struct FloorAgeResultView: View {
    let result: FloorAgeResult
    /// The Floor Age from the check before this one, to celebrate a drop.
    var previous: Int?
    var onDone: (() -> Void)?

    @State private var sharing = false

    private var drop: Int? {
        guard let previous, previous > result.floorAge else { return nil }
        return previous - result.floorAge
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                if let drop {
                    HStack(spacing: Space.l) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 38))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your Floor Age dropped").font(.caption.weight(.heavy)).tracking(1.4).textCase(.uppercase).opacity(0.9)
                            Text(drop == 1 ? String(localized: "1 year younger") : String(localized: "\(drop) years younger")).font(.display(.title2))
                            Text("From \(previous ?? 0) to \(result.floorAge). Your training is working.").font(.subheadline).opacity(0.9)
                        }
                        Spacer(minLength: 0)
                    }
                    .heroCard(.calories, symbol: "chart.line.downtrend.xyaxis")
                }
                FloorAgeCard(result: result)
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("By area").font(.display(.title3))
                    ForEach(FloorTest.allCases) { test in
                        AreaRow(test: test, result: result)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tintedCard(.floorAge)

                if let weakest = result.weakest {
                    HStack(alignment: .top, spacing: Space.l) {
                        FeatureBadge(feature: weakest.feature, symbol: "target", size: 42)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Eyebrow("Focus", feature: weakest.feature)
                            Text("Your plan now focuses on \(weakest.area.lowercased()). Retest in about 4 weeks to see your Floor Age drop.")
                                .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tintedCard(weakest.feature)
                }
                Text("Floor Age is a fitness estimate from simple movement tests, not a medical diagnosis.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button { sharing = true } label: {
                    Label("Share my Floor Age", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(Feature.floorAge.inkColors[1])
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.l)
                        .background(Feature.floorAge.tint.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                if let onDone {
                    Button {
                        onDone()
                    } label: {
                        Text("Done")
                    }
                    .buttonStyle(GradientButtonStyle(feature: .floorAge))
                }
            }
            .padding()
        }
        .background(AppBackground())
        .overlay {
            if drop != nil {
                ConfettiView(colors: Feature.calories.colors + Feature.challenge.colors + [.white])
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $sharing) { ShareCardView(result: result) }
    }
}

/// The big number at the top of the result.
struct FloorAgeCard: View {
    let result: FloorAgeResult

    var body: some View {
        let difference = result.floorAge - result.age
        VStack(spacing: Space.s) {
            Text("MY FLOOR AGE")
                .font(.caption.weight(.heavy))
                .tracking(3)
                .opacity(0.9)
            Text("\(result.floorAge)")
                .font(.system(size: 108, weight: .heavy, design: .rounded))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
            Label(difference > 0 ? "\(difference) years older than my age (\(result.age))"
                  : difference < 0 ? "\(-difference) years younger than my age (\(result.age))"
                  : "Right on my age (\(result.age))",
                  systemImage: difference > 0 ? "arrow.up.right" : difference < 0 ? "arrow.down.right" : "equal")
                .font(.display(.headline))
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
                .background(.white.opacity(0.2), in: Capsule())
            Text("How old does your body move?")
                .font(.footnote.italic())
                .opacity(0.85)
                .padding(.top, Space.s)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.l)
        .heroCard(.floorAge, padding: Space.xl, cornerRadius: Radius.large)
    }
}

private struct AreaRow: View {
    let test: FloorTest
    let result: FloorAgeResult

    var body: some View {
        HStack(spacing: Space.m) {
            FeatureBadge(feature: test.feature, symbol: test.symbol, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(test.area).font(.subheadline.weight(.semibold))
                Text(test.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let age = result.equivalentAge(test) {
                let older = age > Double(result.age) + 2
                Text("moves like \(Int(age.rounded()))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.xs)
                    .background(older ? Feature.steps.gradient : Feature.calories.gradient, in: Capsule())
            } else {
                Text("skipped").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.xs)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }
}
