import SwiftUI

struct FloorAgeResultView: View {
    let result: FloorAgeResult
    var onDone: (() -> Void)?

    @State private var sharing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                FloorAgeCard(result: result)
                VStack(alignment: .leading, spacing: 14) {
                    Text("By area").font(.display(.title3))
                    ForEach(FloorTest.allCases) { test in
                        AreaRow(test: test, result: result)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tintedCard(.floorAge)

                if let weakest = result.weakest {
                    HStack(alignment: .top, spacing: 14) {
                        FeatureBadge(feature: weakest.feature, symbol: "target", size: 42)
                        VStack(alignment: .leading, spacing: 4) {
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
                        .foregroundStyle(Feature.floorAge.colors[1])
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
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
        .sheet(isPresented: $sharing) { ShareCardView(result: result) }
    }
}

/// The big number at the top of the result.
struct FloorAgeCard: View {
    let result: FloorAgeResult

    var body: some View {
        let difference = result.floorAge - result.age
        VStack(spacing: 6) {
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
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.white.opacity(0.2), in: Capsule())
            Text("How old does your body move?")
                .font(.footnote.italic())
                .opacity(0.85)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .heroCard(.floorAge, padding: 20, cornerRadius: 30)
    }
}

private struct AreaRow: View {
    let test: FloorTest
    let result: FloorAgeResult

    var body: some View {
        HStack(spacing: 12) {
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(older ? Feature.steps.gradient : Feature.calories.gradient, in: Capsule())
            } else {
                Text("skipped").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }
}
