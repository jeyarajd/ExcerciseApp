import SwiftUI

struct FloorAgeResultView: View {
    let result: FloorAgeResult
    var onDone: (() -> Void)?

    @State private var shareImage: Image?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                FloorAgeCard(result: result)
                VStack(alignment: .leading, spacing: 12) {
                    Text("By area").font(.headline)
                    ForEach(FloorTest.allCases) { test in
                        AreaRow(test: test, result: result)
                    }
                }
                .card()

                if let weakest = result.weakest {
                    Label("Your plan now focuses on \(weakest.area.lowercased()). Retest in about 4 weeks to see your Floor Age drop.",
                          systemImage: "target")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Floor Age is a fitness estimate from simple movement tests, not a medical diagnosis.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let shareImage {
                    ShareLink(item: shareImage, preview: SharePreview("My Floor Age", image: shareImage)) {
                        Label("Share my Floor Age", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                if let onDone {
                    Button {
                        onDone()
                    } label: {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
        }
        .background(AppBackground())
        .onAppear { renderShareImage() }
    }

    @MainActor
    private func renderShareImage() {
        let renderer = ImageRenderer(content: FloorAgeCard(result: result).frame(width: 360).padding(20).background(Color.white))
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            shareImage = Image(uiImage: uiImage)
        }
    }
}

/// The big number. Also rendered to an image for sharing.
struct FloorAgeCard: View {
    let result: FloorAgeResult

    var body: some View {
        let difference = result.floorAge - result.age
        VStack(spacing: 8) {
            Text("MY FLOOR AGE")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.85))
            Text("\(result.floorAge)")
                .font(.system(size: 88, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(difference > 0 ? "\(difference) years older than my age (\(result.age))"
                 : difference < 0 ? "\(-difference) years younger than my age (\(result.age))"
                 : "Right on my age (\(result.age))")
                .font(.headline)
                .foregroundStyle(.white)
            Text("How old does your body move?")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 4)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.95, green: 0.5, blue: 0.16), Color(red: 0.8, green: 0.25, blue: 0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }
}

private struct AreaRow: View {
    let test: FloorTest
    let result: FloorAgeResult

    var body: some View {
        HStack {
            Image(systemName: test.symbol)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading) {
                Text(test.area)
                Text(test.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let age = result.equivalentAge(test) {
                Text("moves like \(Int(age.rounded()))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(age > Double(result.age) + 2 ? Color.orange : Color.green)
            } else {
                Text("skipped").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
