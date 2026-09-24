import PhotosUI
import SwiftUI
import UIKit

/// "Snap your plate": take or pick a photo, get on-device suggestions of what's on it, confirm the
/// items and servings, and add them to the food log. The photo is analysed on the iPhone and then
/// discarded; it's never saved or sent.
struct FoodPhotoView: View {
    let day: Date
    /// Screenshots: show these results for a placeholder photo instead of taking one.
    var preview: [FoodRecognizer.Guess]? = nil

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var guesses: [FoodRecognizer.Guess] = []
    /// Food name -> servings, for the ticked items.
    @State private var picked: [String: Double] = [:]
    @State private var analyzing = false
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    photoArea
                    captureButtons
                    if analyzing {
                        ProgressView("Looking at your plate…").padding()
                    } else if !guesses.isEmpty {
                        results
                    } else if image != nil || preview != nil {
                        Label("Couldn't recognise this plate. Add the foods from the list instead.", systemImage: "questionmark.circle")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }
                    Text("Your photo is checked on this iPhone and never saved or sent. Photos can't show portion size, so set the servings yourself.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .padding(.bottom, 80)
            }
            .background(AppBackground())
            .safeAreaInset(edge: .bottom) { addBar }
            .navigationTitle("Snap your plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { photo in analyze(photo) }
                .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let photo = UIImage(data: data) {
                    analyze(photo)
                }
            }
        }
        .onAppear {
            if let preview, guesses.isEmpty { show(preview) }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var photoArea: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .clipShape(shape)
        } else {
            VStack(spacing: Space.m) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                Text(preview == nil ? "Take a photo of your plate from above" : "Your photo")
                    .font(.headline)
                Text("Good light and the whole plate in view work best.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(Color.accentColor.opacity(0.08), in: shape)
            .overlay(shape.strokeBorder(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        }
    }

    private var captureButtons: some View {
        HStack(spacing: Space.m) {
            if cameraAvailable {
                Button {
                    showingCamera = true
                } label: {
                    Label(image == nil ? "Take photo" : "Retake", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Looks like").font(.headline)
            FlowChips(labels: guesses.map { "\($0.title) \(Int(($0.confidence * 100).rounded()))%" })
            Divider()
            Text("Tick what's on your plate").font(.subheadline).foregroundStyle(.secondary)
            ForEach(guesses, id: \.label) { guess in
                ForEach(guess.items) { item in
                    row(item)
                }
            }
        }
        .card()
    }

    private func row(_ item: FoodItem) -> some View {
        let servings = picked[item.name]
        return VStack(alignment: .leading, spacing: Space.s) {
            Button {
                picked[item.name] = servings == nil ? 1 : nil
            } label: {
                HStack {
                    Image(systemName: servings == nil ? "circle" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(servings == nil ? Color.secondary : Color.accentColor)
                    VStack(alignment: .leading) {
                        Text(item.displayName).foregroundStyle(Color.primary)
                        Text("\(item.displayServing) · \(item.kcal) kcal").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let servings {
                        Text("\(Int((Double(item.kcal) * servings).rounded())) kcal").monospacedDigit().font(.subheadline.weight(.semibold))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let servings {
                Stepper("\(servings.formatted()) × \(item.displayServing)",
                        value: Binding(get: { servings }, set: { picked[item.name] = $0 }), in: 0.5...10, step: 0.5)
                    .font(.subheadline)
                    .padding(.leading, 34)
            }
        }
    }

    @ViewBuilder
    private var addBar: some View {
        let items = FoodLibrary.items.filter { picked[$0.name] != nil }
        if !items.isEmpty {
            let total = items.reduce(0) { $0 + Int((Double($1.kcal) * (picked[$1.name] ?? 1)).rounded()) }
            Button {
                let when = Calendar.current.isDateInToday(day) ? Date() : Calendar.current.date(byAdding: .hour, value: 12, to: day) ?? day
                for item in items {
                    model.addFood(FoodEntry(date: when, name: item.name, kcal: item.kcal, servings: picked[item.name] ?? 1))
                }
                dismiss()
            } label: {
                Group {
                    if items.count == 1 {
                        Text("Add 1 item · \(total.formatted()) kcal")
                    } else {
                        Text("Add \(items.count) items · \(total.formatted()) kcal")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }

    // MARK: - Recognition

    private func analyze(_ photo: UIImage) {
        image = photo
        guesses = []
        picked = [:]
        guard let cgImage = photo.cgImage else { return }
        analyzing = true
        Task {
            let observations = (try? await FoodRecognizer.classify(cgImage, orientation: CGImagePropertyOrientation(photo.imageOrientation))) ?? []
            show(FoodRecognizer.guesses(from: observations))
            analyzing = false
        }
    }

    /// Shows suggestions, ticking the top food for each confident label.
    private func show(_ results: [FoodRecognizer.Guess]) {
        guesses = results
        for guess in results where guess.confidence >= FoodRecognizer.likely {
            if let first = guess.items.first { picked[first.name] = 1 }
        }
    }
}

/// Labels laid out in rows that wrap.
private struct FlowChips: View {
    let labels: [String]

    var body: some View {
        FlowLayout(spacing: Space.s) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// The system camera, for one photo.
struct CameraPicker: UIViewControllerRepresentable {
    var onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let photo = info[.originalImage] as? UIImage { parent.onPhoto(photo) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
