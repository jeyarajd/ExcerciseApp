import CoreGraphics
import Foundation
import Vision

/// Suggests foods from a photo of a plate, entirely on the device, using Apple's built-in Vision
/// image classifier. It knows general food labels (pizza, pasta, burger, sushi, curry, rice, naan,
/// biryani, samosa, soup, yogurt, fruit…) which are mapped to items in `FoodLibrary`. It can't see portion sizes, so the
/// person confirms the items and servings. The photo is never saved or sent anywhere.
enum FoodRecognizer {
    struct Guess: Equatable {
        /// Vision's label, e.g. "curry".
        let label: String
        let confidence: Float
        /// Matching foods from `FoodLibrary`, most likely first.
        let items: [FoodItem]

        var title: String {
            FoodLibrary.localized(label.replacingOccurrences(of: "_drink", with: "").replacingOccurrences(of: "_", with: " ").capitalized)
        }
    }

    /// Vision label -> FoodLibrary names. Specific labels first; generic ones ("fruit") come last
    /// and only fill in when nothing specific was seen.
    static let suggestions: [String: [String]] = [
        // Indian dishes
        "biryani": ["Chicken biryani", "Veg biryani"],
        "curry": ["Dal", "Chicken curry", "Mixed veg sabzi", "Chole", "Rajma", "Paneer butter masala"],
        "naan": ["Naan", "Roti / chapati", "Plain paratha"],
        "samosa": ["Samosa"],
        // Grains, breads and mains
        "rice": ["Rice, cooked", "Fried rice", "Jeera rice", "Veg pulao"],
        "bread": ["Toast with butter", "Roti / chapati", "Bread"],
        "white_bread": ["Toast with butter", "Bread"],
        "bagel": ["Bagel with cream cheese"],
        "croissant": ["Croissant"],
        "pancake": ["Pancakes", "Plain dosa", "Uttapam"],
        "waffle": ["Pancakes"],
        "dumpling": ["Dumplings", "Idli", "Medu vada"],
        "soup": ["Soup", "Sambar", "Dal", "Rasam"],
        "oatmeal": ["Oatmeal", "Oats porridge with milk", "Upma", "Poha"],
        "pizza": ["Pizza"],
        "pasta": ["Pasta with tomato sauce", "Spaghetti bolognese", "Mac and cheese", "Noodle stir-fry"],
        "meatball": ["Spaghetti bolognese"],
        "hamburger": ["Burger"],
        "sandwich": ["Chicken sandwich", "Wrap"],
        "taco": ["Tacos", "Burrito"],
        "sushi": ["Sushi"],
        "steak": ["Steak"],
        // Vegetables and salads
        "salad": ["Green salad", "Caesar salad"],
        "vegetable": ["Mixed veg sabzi", "Green salad"],
        "spinach": ["Palak paneer"],
        "green_beans": ["Mixed veg sabzi"],
        "eggplant": ["Mixed veg sabzi"],
        "potato": ["French fries", "Aloo sabzi"],
        "fries": ["French fries", "Aloo sabzi"],
        // Protein and dairy
        "yogurt": ["Curd / dahi", "Yogurt with granola", "Raita"],
        "cheese": ["Cheese"],
        "egg": ["Boiled egg", "Scrambled eggs", "Egg curry"],
        "omelet": ["Omelette"],
        "fried_egg": ["Omelette"],
        "scrambled_eggs": ["Scrambled eggs"],
        "fried_chicken": ["Fried chicken", "Chicken curry"],
        "grilled_chicken": ["Grilled chicken breast", "Chicken curry", "Butter chicken"],
        "meat": ["Chicken curry", "Grilled chicken breast"],
        "fish": ["Salmon fillet", "Fish curry", "Fish and chips"],
        "seafood": ["Salmon fillet", "Fish curry"],
        // Drinks
        "tea_drink": ["Chai with sugar"],
        "coffee": ["Latte", "Black coffee", "Coffee with milk and sugar"],
        "juice": ["Orange juice", "Fresh fruit juice"],
        "milkshake": ["Milkshake", "Lassi, sweet"],
        // Fruit and nuts
        "banana": ["Banana"],
        "apple": ["Apple"],
        "mango": ["Mango"],
        "papaya": ["Papaya"],
        "guava": ["Guava"],
        "oranges": ["Orange"],
        "citrus_fruit": ["Orange"],
        "grape": ["Grapes"],
        "strawberry": ["Strawberries"],
        "blueberry": ["Blueberries"],
        "watermelon": ["Watermelon"],
        "melon": ["Watermelon"],
        "pineapple": ["Pineapple"],
        "pear": ["Pear"],
        "peanut": ["Roasted peanuts"],
        "almond": ["Almonds"],
        "nut": ["Mixed nuts", "Almonds", "Roasted peanuts"],
        "popcorn": ["Popcorn"],
        // Sweets
        "cookie": ["Cookie", "Biscuits"],
        "donut": ["Donut"],
        "ice_cream": ["Ice cream"],
        "frozen_dessert": ["Ice cream", "Kheer"],
        "chocolate": ["Chocolate bar"],
        "cake": ["Cake", "Muffin"],
        "cupcake": ["Muffin", "Cake"],
        "cheesecake": ["Cake"],
        "dessert": ["Gulab jamun", "Kheer", "Ladoo", "Jalebi", "Ice cream", "Cake"],
        "candy": ["Ladoo", "Jalebi", "Chocolate bar"],
        // Generic
        "fruit": ["Banana", "Apple", "Mango", "Papaya", "Grapes"],
        "drink": ["Chai with sugar", "Buttermilk / chaas", "Orange juice"],
    ]
    private static let generic: Set<String> = ["fruit", "drink", "vegetable", "meat", "dessert"]

    /// Labels below this are ignored; at or above `likely` a suggestion starts ticked.
    static let minimumConfidence: Float = 0.12
    static let likely: Float = 0.35

    /// Turns classifier results into food suggestions: known labels only, confident first, generic
    /// labels only when nothing specific was found, and each food suggested once.
    static func guesses(from observations: [(label: String, confidence: Float)],
                        preferIndian: Bool = Region.prefersIndianFood) -> [Guess] {
        let byName = Dictionary(FoodLibrary.items.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        // Local dishes first within each suggestion (a stable sort keeps the listed order otherwise).
        func rank(_ item: FoodItem) -> Int { (item.cuisine == .indian) == preferIndian ? 0 : 1 }
        let known = observations
            .filter { $0.confidence >= minimumConfidence && suggestions[$0.label] != nil }
            .sorted { $0.confidence > $1.confidence }
        let specific = known.filter { !generic.contains($0.label) }
        let chosen = specific.isEmpty ? known : specific + known.filter { generic.contains($0.label) && $0.confidence >= likely }
        var seen = Set<String>()
        return chosen.prefix(6).compactMap { observation in
            let items = (suggestions[observation.label] ?? []).compactMap { byName[$0] }
                .enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
                .filter { seen.insert($0.name).inserted }
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
