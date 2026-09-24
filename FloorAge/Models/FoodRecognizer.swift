import CoreGraphics
import Foundation
import Vision

/// Suggests foods from a photo of a plate, entirely on the device, using Apple's built-in Vision
/// image classifier. It knows general food labels (curry, rice, naan, biryani, samosa, soup,
/// yogurt, fruit…) which are mapped to items in `FoodLibrary`. It can't see portion sizes, so the
/// person confirms the items and servings. The photo is never saved or sent anywhere.
enum FoodRecognizer {
    struct Guess: Equatable {
        /// Vision's label, e.g. "curry".
        let label: String
        let confidence: Float
        /// Matching foods from `FoodLibrary`, most likely first.
        let items: [FoodItem]

        var title: String {
            label.replacingOccurrences(of: "_drink", with: "").replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Vision label -> FoodLibrary names. Specific labels first; generic ones ("fruit") come last
    /// and only fill in when nothing specific was seen.
    static let suggestions: [String: [String]] = [
        "biryani": ["Chicken biryani", "Veg biryani"],
        "curry": ["Dal", "Chicken curry", "Mixed veg sabzi", "Chole", "Rajma", "Paneer butter masala"],
        "naan": ["Naan", "Roti / chapati", "Plain paratha"],
        "samosa": ["Samosa"],
        "rice": ["Rice, cooked", "Jeera rice", "Veg pulao"],
        "bread": ["Roti / chapati", "Bread"],
        "white_bread": ["Bread"],
        "pancake": ["Plain dosa", "Uttapam", "Plain paratha"],
        "dumpling": ["Idli", "Medu vada"],
        "soup": ["Sambar", "Dal", "Rasam"],
        "oatmeal": ["Oats porridge with milk", "Upma", "Poha", "Pongal"],
        "salad": ["Green salad"],
        "vegetable": ["Mixed veg sabzi", "Green salad"],
        "spinach": ["Palak paneer"],
        "green_beans": ["Mixed veg sabzi"],
        "eggplant": ["Mixed veg sabzi"],
        "potato": ["Aloo sabzi"],
        "fries": ["Aloo sabzi"],
        "yogurt": ["Curd / dahi", "Raita"],
        "egg": ["Boiled egg", "Egg curry"],
        "omelet": ["Omelette"],
        "fried_egg": ["Omelette"],
        "scrambled_eggs": ["Omelette"],
        "fried_chicken": ["Chicken curry", "Butter chicken"],
        "grilled_chicken": ["Chicken curry", "Butter chicken"],
        "meat": ["Chicken curry"],
        "fish": ["Fish curry"],
        "seafood": ["Fish curry"],
        "tea_drink": ["Chai with sugar"],
        "coffee": ["Coffee with milk and sugar"],
        "juice": ["Fresh fruit juice"],
        "milkshake": ["Lassi, sweet"],
        "banana": ["Banana"],
        "apple": ["Apple"],
        "mango": ["Mango"],
        "papaya": ["Papaya"],
        "guava": ["Guava"],
        "oranges": ["Orange"],
        "citrus_fruit": ["Orange"],
        "peanut": ["Roasted peanuts"],
        "almond": ["Almonds"],
        "nut": ["Almonds", "Roasted peanuts"],
        "cookie": ["Biscuits"],
        "dessert": ["Gulab jamun", "Kheer", "Ladoo", "Jalebi"],
        "candy": ["Ladoo", "Jalebi"],
        "cake": ["Ladoo"],
        // Generic
        "fruit": ["Banana", "Apple", "Mango", "Papaya"],
        "drink": ["Chai with sugar", "Buttermilk / chaas"],
    ]
    private static let generic: Set<String> = ["fruit", "drink", "vegetable", "meat", "dessert"]

    /// Labels below this are ignored; at or above `likely` a suggestion starts ticked.
    static let minimumConfidence: Float = 0.12
    static let likely: Float = 0.35

    /// Turns classifier results into food suggestions: known labels only, confident first, generic
    /// labels only when nothing specific was found, and each food suggested once.
    static func guesses(from observations: [(label: String, confidence: Float)]) -> [Guess] {
        let byName = Dictionary(FoodLibrary.items.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let known = observations
            .filter { $0.confidence >= minimumConfidence && suggestions[$0.label] != nil }
            .sorted { $0.confidence > $1.confidence }
        let specific = known.filter { !generic.contains($0.label) }
        let chosen = specific.isEmpty ? known : specific + known.filter { generic.contains($0.label) && $0.confidence >= likely }
        var seen = Set<String>()
        return chosen.prefix(6).compactMap { observation in
            let items = (suggestions[observation.label] ?? []).compactMap { byName[$0] }.filter { seen.insert($0.name).inserted }
            return items.isEmpty ? nil : Guess(label: observation.label, confidence: observation.confidence, items: items)
        }
    }

    /// Runs Vision's classifier on the photo (off the main thread).
    static func classify(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) async throws -> [(label: String, confidence: Float)] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
            return (request.results ?? []).map { ($0.identifier, $0.confidence) }
        }.value
    }
}
