import Charts
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach
    @State private var showingTest = false

    var body: some View {
        NavigationStack {
            List {
                if model.results.count >= 2 {
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
                        ForEach(model.results.reversed()) { result in
                            NavigationLink {
                                FloorAgeResultView(result: result)
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
            .navigationTitle("Progress")
            .fullScreenCover(isPresented: $showingTest) {
                FloorAgeTestView()
                    .environmentObject(model)
                    .environmentObject(voice)
            }
        }
    }
}
