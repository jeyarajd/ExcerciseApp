import SwiftUI

/// What Floor Age Plus unlocks. The Floor Age check, daily sessions with the coach, steps,
/// calories, BMI and all safety guidance stay free.
enum PlusFeature: CaseIterable, Identifiable {
    case plan, family, foodPhoto, sleep, pelvicFloor, history

    var id: Self { self }

    var title: String {
        switch self {
        case .plan: String(localized: "Training plan")
        case .family: String(localized: "Family profiles")
        case .foodPhoto: String(localized: "Food photo calories")
        case .sleep: String(localized: "Sleep tracking")
        case .pelvicFloor: String(localized: "Pelvic floor programme")
        case .history: String(localized: "Progress over time")
        }
    }

    var detail: String {
        switch self {
        case .plan: String(localized: "A weekly walking or Couch to 5K plan with strength sets, built for your weight and age.")
        case .family: String(localized: "Test and coach your parents or partner on this iPhone, each with their own Floor Age and plan.")
        case .foodPhoto: String(localized: "Snap your plate for calorie suggestions, checked on your iPhone.")
        case .sleep: String(localized: "Log your nights or read them from Apple Health, against the range for your age.")
        case .pelvicFloor: String(localized: "Guided Kegel sessions any time, plus Kegels at the end of each daily session.")
        case .history: String(localized: "Your Floor Age chart and every past check.")
        }
    }

    var symbol: String {
        switch self {
        case .plan: "calendar.badge.checkmark"
        case .family: "person.2.fill"
        case .foodPhoto: "camera.fill"
        case .sleep: "moon.stars.fill"
        case .pelvicFloor: "figure.mind.and.body"
        case .history: "chart.line.uptrend.xyaxis"
        }
    }

    var feature: Feature {
        switch self {
        case .plan: .plan
        case .family: .glance
        case .foodPhoto: .calories
        case .sleep: .sleep
        case .pelvicFloor: .floorAge
        case .history: .bmi
        }
    }
}

/// The Floor Age Plus screen: what it unlocks, the one-time price, and Restore Purchases.
struct PlusView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    /// The feature the person tapped to get here, listed first.
    var highlight: PlusFeature?
    @State private var alert: String?

    private var features: [PlusFeature] {
        guard let highlight else { return PlusFeature.allCases }
        return [highlight] + PlusFeature.allCases.filter { $0 != highlight }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    hero
                    VStack(spacing: Space.m) {
                        ForEach(features) { row($0) }
                    }
                    purchaseArea
                }
                .padding()
            }
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await store.loadProduct() }
            .messageAlert($alert)
        }
    }

    private var hero: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "crown.fill")
                .font(.system(size: 46))
                .foregroundStyle(Feature.gold)
                .shadow(color: Feature.gold.opacity(0.6), radius: 14)
            Text("Floor Age Plus")
                .font(.display(.largeTitle))
            Text(store.hasPlus ? "Unlocked. Thank you for supporting Floor Age!" : "Unlock everything, once. No subscription.")
                .font(.callout)
                .opacity(0.9)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.m)
        .heroCard(.plus, padding: Space.xl, cornerRadius: Radius.large)
    }

    private func row(_ item: PlusFeature) -> some View {
        HStack(spacing: Space.l) {
            FeatureBadge(feature: item.feature, symbol: item.symbol, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.display(.headline))
                Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: store.hasPlus ? "checkmark.circle.fill" : "lock.fill")
                .foregroundStyle(store.hasPlus ? AnyShapeStyle(Feature.calories.gradient) : AnyShapeStyle(Feature.plus.ink))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedCard(item == highlight ? item.feature : .plus, padding: Space.l)
    }

    @ViewBuilder
    private var purchaseArea: some View {
        VStack(spacing: Space.m) {
            if store.hasPlus {
                Button("Done") { dismiss() }
                    .buttonStyle(GradientButtonStyle(feature: .plus))
            } else {
                Button {
                    Task { alert = await store.purchase() }
                } label: {
                    if store.busy {
                        ProgressView().tint(.white)
                    } else if let price = store.price {
                        Label("Unlock for \(price)", systemImage: "crown.fill")
                    } else {
                        Label("Unlock Floor Age Plus", systemImage: "crown.fill")
                    }
                }
                .buttonStyle(GradientButtonStyle(feature: .plus))
                .disabled(store.price == nil || store.busy)
                if store.price == nil {
                    Text("Connecting to the App Store…").font(.caption).foregroundStyle(.secondary)
                }
                Button("Restore Purchases") {
                    Task { alert = await store.restore() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Feature.plus.inkColors[0])
                .disabled(store.busy)
            }
            Text("A one-time purchase, charged to your Apple Account. Your data stays on your iPhone either way. The Floor Age check, daily sessions with the coach, steps, calories, BMI and all safety guidance stay free.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Space.xs)
    }
}

/// Stands in for a Plus feature when it's locked: what it does, and a tap opens the Plus screen.
struct PlusLockedCard: View {
    let feature: PlusFeature
    @EnvironmentObject private var store: Store
    @State private var showingPlus = false

    var body: some View {
        Button { showingPlus = true } label: {
            HStack(spacing: Space.l) {
                FeatureBadge(feature: feature.feature, symbol: feature.symbol, size: 46)
                VStack(alignment: .leading, spacing: Space.xs) {
                    PlusBadge()
                    Text(feature.title).font(.display(.headline))
                    Text(feature.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "lock.fill").foregroundStyle(Feature.plus.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tintedCard(.plus)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPlus) {
            PlusView(highlight: feature).environmentObject(store)
        }
    }
}

/// A small "Plus" capsule with a crown, next to locked features.
struct PlusBadge: View {
    var body: some View {
        Label("Plus", systemImage: "crown.fill")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 3)
            .background(Feature.plus.gradient, in: Capsule())
    }
}

extension View {
    /// Shows a message from the store (purchase pending, nothing to restore, …) and clears it.
    func messageAlert(_ message: Binding<String?>) -> some View {
        alert("Floor Age Plus", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
