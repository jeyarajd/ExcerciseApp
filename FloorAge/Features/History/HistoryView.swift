import Charts
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach
    @EnvironmentObject private var store: Store
    @State private var showingTest = false

    /// Tight around the Floor Ages and the person's age, so real progress is visible.
    private var chartRange: ClosedRange<Int> {
        let values = model.results.map(\.floorAge) + [model.profile?.age].compactMap { $0 }
        let low = (values.min() ?? 20) - 5, high = (values.max() ?? 80) + 5
        return max(0, low / 5 * 5)...((high + 4) / 5 * 5)
    }

    var body: some View {
        NavigationStack {
            List {
                if model.results.count >= 2, !store.hasPlus {
                    Section {
                        PlusLockedCard(feature: .history)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    }
                } else if model.results.count >= 2 {
                    Section("Floor Age over time") {
                        Chart {
                            ForEach(model.results) { result in
                                LineMark(x: .value("Date", result.date), y: .value("Floor Age", result.floorAge))
                                    .interpolationMethod(.monotone)
                                PointMark(x: .value("Date", result.date), y: .value("Floor Age", result.floorAge))
                            }
                            if let age = model.profile?.age {
                                RuleMark(y: .value("Your age", age))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .annotation(position: .top, alignment: .leading) {
                                        Text("Your age").font(.caption2).foregroundStyle(.secondary)
                                    }
                            }
                        }
                        .chartYScale(domain: chartRange)
                        .frame(height: 200)
                    }
                }

                Section {
                    Button {
                        showingTest = true
                    } label: {
                        Label(model.results.isEmpty ? "Take the Floor Age check" : "Retest my Floor Age",
                              systemImage: "figure.cross.training")
                    }
                }

                if !model.results.isEmpty {
                    Section("Checks") {
                        // Without Plus, only the latest check is kept on view.
                        ForEach(Array(model.results.reversed().prefix(store.hasPlus ? .max : 1))) { result in
                            NavigationLink {
                                FloorAgeResultView(result: result, history: Array(model.results.prefix { $0.id != result.id }))
                                    .navigationTitle(result.date.formatted(date: .abbreviated, time: .omitted))
                            } label: {
                                HStack {
                                    Text(result.date.formatted(date: .abbreviated, time: .omitted))
                                    Spacer()
                                    Text("Floor Age \(result.floorAge)").bold()
                                }
                            }
                        }
                    }
                }

                Section("Sessions") {
                    LabeledContent("Total sessions", value: "\(model.sessionDays.count)")
                    LabeledContent("Last 7 days", value: "\(model.lastSevenDays.filter { $0 }.count)")
                }
            }
            .appBackground()
            .navigationTitle("Progress")
            .fullScreenCover(isPresented: $showingTest) {
                FloorAgeTestView()
                    .environmentObject(model)
                    .environmentObject(voice)
            }
        }
    }
}
