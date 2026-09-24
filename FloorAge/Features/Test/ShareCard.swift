import CoreImage.CIFilterBuiltins
import SwiftUI

/// Where people can get the app. Set `appStoreID` once App Store Connect assigns one (the number in
/// the app's App Store link); until then the share card asks people to search instead of showing a
/// QR code.
enum AppLinks {
    static let appStoreID: String? = nil

    static var appStoreURL: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)") }
    }

    /// The end of a share message: the link, or how to find the app until there is one.
    static var findTheApp: String {
        appStoreURL?.absoluteString ?? String(localized: "search “Floor Age” on the App Store.")
    }
}

/// A story-sized (9:16) picture of a Floor Age result with a challenge, for WhatsApp, Instagram and
/// messages. Rendered at 1080 × 1920.
struct ShareCard: View {
    let result: FloorAgeResult
    var showAge = true

    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        let difference = result.floorAge - result.age
        ShareCardFrame {
            Text("MY FLOOR AGE")
                .font(.system(size: 13, weight: .heavy))
                .tracking(3)
                .opacity(0.9)
            Text("\(result.floorAge)")
                .font(.system(size: 150, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            if showAge {
                Text(difference > 0 ? "\(difference) years older than my age (\(result.age))"
                     : difference < 0 ? "\(-difference) years younger than my age (\(result.age))"
                     : "Right on my age (\(result.age))")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.2), in: Capsule())
            }

            VStack(spacing: 8) {
                ForEach(FloorTest.allCases) { test in
                    if let age = result.equivalentAge(test) {
                        HStack(spacing: 10) {
                            Image(systemName: test.symbol)
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 28, height: 28)
                                .background(test.feature.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(test.area).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.65)
                            Spacer(minLength: 4)
                            Text("moves like \(Int(age.rounded()))").font(.system(size: 13, weight: .bold)).opacity(0.9)
                        }
                    }
                }
            }
            .padding(14)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 20)
        }
    }

    @MainActor
    func render() -> UIImage? { renderShareCard() }
}

/// What every share card has around its own content: the app name at the top, the invitation to
/// find your own Floor Age at the bottom, and the brand gradient behind.
struct ShareCardFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "figure.cross.training")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Floor Age").font(.system(size: 22, weight: .bold, design: .serif))
                Spacer()
            }
            .padding(.top, 34)

            Spacer(minLength: 12)

            content

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Text("Can you get up off the floor without using your hands?")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Feature.floorAge.colors[1])
                HStack(spacing: 12) {
                    if let url = AppLinks.appStoreURL, let qr = QRCode.image(for: url.absoluteString) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 64, height: 64)
                    }
                    Text(AppLinks.appStoreURL == nil
                         ? "Find your Floor Age: 4 tests, 10 minutes. Search “Floor Age” on the App Store."
                         : "Find your Floor Age: 4 tests, 10 minutes. Scan to get the app.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.black.opacity(0.7))
                        .multilineTextAlignment(AppLinks.appStoreURL == nil ? .center : .leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.bottom, 30)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .frame(width: ShareCard.size.width, height: ShareCard.size.height)
        .background {
            ZStack {
                LinearGradient(colors: Feature.floorAge.colors + [Color(red: 0.45, green: 0.12, blue: 0.3)],
                               startPoint: .topLeading, endPoint: .bottom)
                Circle().fill(.white.opacity(0.25)).frame(width: 300).blur(radius: 70).offset(x: 120, y: -230)
                Image(systemName: "figure.cross.training")
                    .font(.system(size: 260, weight: .bold))
                    .foregroundStyle(.white.opacity(0.07))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 110, y: -40)
            }
        }
        .clipped()
    }
}

extension View {
    /// The card as a 1080 × 1920 picture.
    @MainActor
    func renderShareCard() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        return renderer.uiImage
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Preview of the share card, a choice to hide your real age, and the share sheet.
struct ShareCardView: View {
    let result: FloorAgeResult
    @Environment(\.dismiss) private var dismiss
    @AppStorage("shareShowsAge") private var showAge = true
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ShareCard(result: result, showAge: showAge)
                        .scaleEffect(0.78)
                        .frame(width: ShareCard.size.width * 0.78, height: ShareCard.size.height * 0.78)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Feature.floorAge.colors[1].opacity(0.35), radius: 18, y: 10)
                        .accessibilityElement(children: .combine)

                    Toggle("Show my real age", isOn: $showAge)
                        .font(.body.weight(.medium))
                        .tint(Feature.floorAge.colors[1])
                        .tintedCard(.floorAge, padding: 14)

                    if let image {
                        ShareLink(item: Image(uiImage: image),
                                  message: Text(shareMessage),
                                  preview: SharePreview("My Floor Age", image: Image(uiImage: image))) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(GradientButtonStyle(feature: .floorAge))
                    }
                    Text("The picture shows your Floor Age and areas, never your name. It's shared only where you choose.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .background(AppBackground())
            .navigationTitle("Share my Floor Age")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear(perform: render)
            .onChange(of: showAge) { render() }
        }
    }

    private var shareMessage: String {
        let text = String(localized: "My Floor Age is \(result.floorAge). Can you get up off the floor without using your hands? Find your Floor Age:")
        return text + " " + AppLinks.findTheApp
    }

    @MainActor
    private func render() {
        image = ShareCard(result: result, showAge: showAge).render()
    }
}
