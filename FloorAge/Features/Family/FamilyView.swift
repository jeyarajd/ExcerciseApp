import SwiftUI

/// Everyone who trains on this iPhone. Switching changes the whole app to that person; adding
/// family members is part of Floor Age Plus.
struct FamilyView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var showingPlus = false
    @State private var removing: FamilyMember?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.members) { member in
                        Button { choose(member) } label: {
                            MemberRow(member: member, isActive: member.id == model.activeMemberID, isOwner: member.id == model.owner.id,
                                      locked: member.id != model.owner.id && !store.hasPlus)
                        }
                        .tint(.primary)
                        .swipeActions {
                            if member.id != model.owner.id {
                                Button("Remove", role: .destructive) { removing = member }
                            }
                        }
                    }
                } header: {
                    Text("Who's training?")
                }

                Section {
                    Button(action: add) {
                        HStack(spacing: Space.m) {
                            FeatureBadge(feature: .glance, symbol: "person.badge.plus", size: 38)
                            Text("Add a family member").font(.headline)
                            Spacer(minLength: 0)
                            if !store.hasPlus { PlusBadge() }
                        }
                    }
                    .tint(.primary)
                } footer: {
                    Text("Everyone gets their own Floor Age, plan and history. Steps, Apple Health sleep and reminders stay with \(model.owner.name.isEmpty ? String(localized: "the owner") : model.owner.name), because they come from this iPhone.")
                }
            }
            .appBackground()
            .navigationTitle("Family")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPlus) {
                PlusView(highlight: .family).environmentObject(store)
            }
            .confirmationDialog(removing.map { String(localized: "Remove \($0.displayName) and all their results from this iPhone?") } ?? "",
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let removing { model.removeMember(removing.id) }
                    Task { await model.refreshReminders() }
                }
            }
        }
    }

    private func choose(_ member: FamilyMember) {
        guard member.id == model.owner.id || store.hasPlus else {
            showingPlus = true
            return
        }
        model.switchMember(member.id)
        Task { await model.refreshReminders() }
        dismiss()
    }

    private func add() {
        guard store.hasPlus else {
            showingPlus = true
            return
        }
        dismiss()
        model.addMember()
    }
}

private struct MemberRow: View {
    let member: FamilyMember
    let isActive: Bool
    let isOwner: Bool
    let locked: Bool

    var body: some View {
        HStack(spacing: Space.l) {
            MemberAvatar(member: member, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name.isEmpty && isOwner ? String(localized: "You") : member.displayName).font(.display(.headline))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let floorAge = member.floorAge {
                VStack(spacing: 0) {
                    Text("\(floorAge)").font(.metric(22)).foregroundStyle(Feature.floorAge.ink)
                    Text("Floor Age").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if isActive {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Feature.calories.gradient)
            } else if locked {
                Image(systemName: "lock.fill").foregroundStyle(Feature.plus.ink)
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var subtitle: String {
        let age = member.age.map { String(localized: "Age \($0)") }
        let role = isOwner ? String(localized: "This iPhone's owner") : nil
        return [age, role].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A round initial in a gradient, for the family switcher and list.
struct MemberAvatar: View {
    let member: FamilyMember
    var size: CGFloat = 36

    var body: some View {
        let feature: Feature = member.gender == .male ? .plan : member.gender == .female ? .floorAge : .bmi
        Text(member.initial)
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(feature.gradient, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
            .shadow(color: feature.colors.last!.opacity(0.3), radius: 4, y: 2)
            .accessibilityHidden(true)
    }
}

/// The avatar button at the top of Today that opens the family list.
struct FamilySwitcherButton: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: Store
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            MemberAvatar(member: model.activeMember, size: 34)
        }
        .accessibilityLabel(Text("Family"))
        .accessibilityValue(Text(model.activeMember.displayName))
        .sheet(isPresented: $showing) {
            FamilyView().environmentObject(model).environmentObject(store)
        }
    }
}

extension FamilyMember {
    var displayName: String { name.isEmpty ? String(localized: "No name") : name }
    var initial: String { name.first.map { String($0).uppercased() } ?? "•" }
}
