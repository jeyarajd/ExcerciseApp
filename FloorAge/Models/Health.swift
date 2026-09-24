import Foundation

/// Which BMI cut-offs to use. International follows WHO (overweight from 25, obese from 30).
/// Asian uses the lower cut-offs recommended for Asian populations, whose health risks start at a
/// lower BMI (WHO expert consultation, Lancet 2004; Misra et al., JAPI 2009 for Asian Indians):
/// overweight from 23, obese from 25. The default follows the phone's region.
enum BMIScale: String, CaseIterable, Identifiable {
    case international, asian

    var id: String { rawValue }
    var label: String { self == .international ? "International (WHO)" : "Asian" }
    var overweight: Double { self == .international ? 25 : 23 }
    var obese: Double { self == .international ? 30 : 25 }

    static var current: BMIScale {
        get { BMIScale(rawValue: UserDefaults.standard.string(forKey: "bmiScale") ?? "") ?? Region.defaultBMIScale }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "bmiScale") }
    }
}

/// Body mass index, categorised on a `BMIScale`.
enum BMI {
    enum Category: String, CaseIterable {
        case underweight, healthy, overweight, obese

        var label: String {
            switch self {
            case .underweight: "Underweight"
            case .healthy: "Healthy"
            case .overweight: "Overweight"
            case .obese: "Obese"
            }
        }

        /// Encouragement, never shaming.
        var message: String {
            switch self {
            case .underweight: "Build strength with your daily sessions and eat regular, balanced meals."
            case .healthy: "You're in the healthy range. Keep moving every day to stay here."
            case .overweight: "Small steps add up: daily walks and your 10-minute sessions make a real difference."
            case .obese: "Every kilo counts. Start gently, walk a little more each week, and check with your doctor for a plan."
            }
        }

        func range(_ scale: BMIScale) -> String {
            switch self {
            case .underweight: "below 18.5"
            case .healthy: "18.5 – \(scale.overweight - 0.1)"
            case .overweight: "\(scale.overweight.formatted()) – \(scale.obese - 0.1)"
            case .obese: "\(scale.obese.formatted()) and above"
            }
        }
    }

    static let underweightBelow = 18.5

    static func value(weightKg: Double, heightCm: Double) -> Double? {
        guard weightKg > 0, heightCm > 0 else { return nil }
        let metres = heightCm / 100
        return weightKg / (metres * metres)
    }

    static func category(_ bmi: Double, scale: BMIScale = .current) -> Category {
        if bmi < underweightBelow { return .underweight }
        if bmi < scale.overweight { return .healthy }
        if bmi < scale.obese { return .overweight }
        return .obese
    }

    /// Weights (kg) that give a healthy BMI at this height.
    static func healthyWeight(heightCm: Double, scale: BMIScale = .current) -> ClosedRange<Double> {
        let m2 = pow(heightCm / 100, 2)
        return (underweightBelow * m2)...((scale.overweight - 0.1) * m2)
    }

    static func pounds(_ kg: Double) -> Double { kg / 0.45359237 }
    static func kilograms(pounds: Double) -> Double { pounds * 0.45359237 }

    static func centimetres(feet: Int, inches: Int) -> Double { Double(feet * 12 + inches) * 2.54 }

    static func feetAndInches(_ cm: Double) -> (feet: Int, inches: Int) {
        let total = Int((cm / 2.54).rounded())
        return (total / 12, total % 12)
    }
}

/// Daily calorie estimate from the Mifflin-St Jeor equation with a lightly active lifestyle.
enum Calories {
    /// Light activity (walking, a short daily session).
    static let activity = 1.375

    static func dailyTarget(age: Int, gender: Gender?, heightCm: Double, weightKg: Double) -> Int {
        // Mifflin-St Jeor: +5 for men, -161 for women; the midpoint when gender isn't given.
        let sexTerm: Double = switch gender {
        case .male: 5
        case .female: -161
        case nil: -78
        }
        let bmr = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + sexTerm
        return Int((bmr * activity / 10).rounded()) * 10
    }
}

/// Steps to distance, using an average adult stride.
enum Steps {
    static let defaultGoal = 8000
    static func kilometres(_ steps: Int) -> Double { Double(steps) * 0.75 / 1000 }

    /// "4.7 km" or "2.9 mi", following the phone's settings.
    static func distance(_ steps: Int) -> String {
        Measurement(value: kilometres(steps), unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(1))))
    }
}

struct WeightEntry: Codable, Equatable {
    var date: Date
    var kg: Double
}

struct FoodEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var name: String
    /// Calories for one serving.
    var kcal: Int
    var servings: Double = 1

    var total: Int { Int((Double(kcal) * servings).rounded()) }
}

/// A food in the built-in list, with calories for a typical serving.
struct FoodItem: Identifiable, Hashable {
    enum Cuisine { case indian, international }

    let name: String
    let serving: String
    let kcal: Int
    var cuisine: Cuisine = .indian
    var id: String { name }
}

/// Common foods with typical portions: Indian dishes (around the averages in the Indian Food
/// Composition Tables, NIN 2017) and international ones (around USDA FoodData Central). Values are
/// approximate and vary with recipe and oil. Listed Indian or international first by region.
enum FoodLibrary {
    static var items: [FoodItem] {
        Region.prefersIndianFood ? indian + international : international + indian
    }

    static let indian: [FoodItem] = [
        // Breads and grains
        FoodItem(name: "Roti / chapati", serving: "1 medium", kcal: 110),
        FoodItem(name: "Phulka", serving: "1", kcal: 70),
        FoodItem(name: "Plain paratha", serving: "1", kcal: 200),
        FoodItem(name: "Aloo paratha", serving: "1", kcal: 290),
        FoodItem(name: "Puri", serving: "2", kcal: 200),
        FoodItem(name: "Naan", serving: "1", kcal: 260),
        FoodItem(name: "Rice, cooked", serving: "1 cup", kcal: 200),
        FoodItem(name: "Brown rice, cooked", serving: "1 cup", kcal: 215),
        FoodItem(name: "Jeera rice", serving: "1 cup", kcal: 250),
        FoodItem(name: "Veg pulao", serving: "1 cup", kcal: 250),
        FoodItem(name: "Chicken biryani", serving: "1 plate", kcal: 500),
        FoodItem(name: "Veg biryani", serving: "1 plate", kcal: 400),
        FoodItem(name: "Khichdi", serving: "1 cup", kcal: 220),
        FoodItem(name: "Bread", serving: "1 slice", kcal: 70),
        // South Indian
        FoodItem(name: "Idli", serving: "1", kcal: 60),
        FoodItem(name: "Plain dosa", serving: "1", kcal: 170),
        FoodItem(name: "Masala dosa", serving: "1", kcal: 350),
        FoodItem(name: "Uttapam", serving: "1", kcal: 200),
        FoodItem(name: "Medu vada", serving: "1", kcal: 140),
        FoodItem(name: "Upma", serving: "1 cup", kcal: 200),
        FoodItem(name: "Pongal", serving: "1 cup", kcal: 260),
        FoodItem(name: "Sambar", serving: "1 small bowl", kcal: 110),
        FoodItem(name: "Rasam", serving: "1 small bowl", kcal: 60),
        FoodItem(name: "Coconut chutney", serving: "2 tbsp", kcal: 70),
        // Breakfast
        FoodItem(name: "Poha", serving: "1 cup", kcal: 250),
        FoodItem(name: "Oats porridge with milk", serving: "1 bowl", kcal: 250),
        FoodItem(name: "Cornflakes with milk", serving: "1 bowl", kcal: 220),
        FoodItem(name: "Boiled egg", serving: "1", kcal: 78),
        FoodItem(name: "Omelette", serving: "2 eggs", kcal: 190),
        // Dals and curries
        FoodItem(name: "Dal", serving: "1 small bowl", kcal: 150),
        FoodItem(name: "Rajma", serving: "1 small bowl", kcal: 180),
        FoodItem(name: "Chole", serving: "1 small bowl", kcal: 210),
        FoodItem(name: "Mixed veg sabzi", serving: "1 small bowl", kcal: 130),
        FoodItem(name: "Aloo sabzi", serving: "1 small bowl", kcal: 170),
        FoodItem(name: "Bhindi fry", serving: "1 small bowl", kcal: 120),
        FoodItem(name: "Palak paneer", serving: "1 small bowl", kcal: 240),
        FoodItem(name: "Paneer butter masala", serving: "1 small bowl", kcal: 320),
        FoodItem(name: "Chicken curry", serving: "1 small bowl", kcal: 250),
        FoodItem(name: "Butter chicken", serving: "1 small bowl", kcal: 330),
        FoodItem(name: "Fish curry", serving: "1 small bowl", kcal: 200),
        FoodItem(name: "Egg curry", serving: "1 small bowl", kcal: 220),
        // Dairy and drinks
        FoodItem(name: "Curd / dahi", serving: "1 small bowl", kcal: 60),
        FoodItem(name: "Raita", serving: "1 small bowl", kcal: 80),
        FoodItem(name: "Buttermilk / chaas", serving: "1 glass", kcal: 40),
        FoodItem(name: "Milk, toned", serving: "1 glass", kcal: 120),
        FoodItem(name: "Lassi, sweet", serving: "1 glass", kcal: 220),
        FoodItem(name: "Chai with sugar", serving: "1 cup", kcal: 90),
        FoodItem(name: "Coffee with milk and sugar", serving: "1 cup", kcal: 90),
        FoodItem(name: "Soft drink", serving: "1 can", kcal: 140),
        FoodItem(name: "Fresh fruit juice", serving: "1 glass", kcal: 110),
        // Snacks and street food
        FoodItem(name: "Samosa", serving: "1", kcal: 260),
        FoodItem(name: "Pakora", serving: "4 pieces", kcal: 180),
        FoodItem(name: "Vada pav", serving: "1", kcal: 290),
        FoodItem(name: "Pav bhaji", serving: "1 plate", kcal: 400),
        FoodItem(name: "Pani puri", serving: "6 pieces", kcal: 200),
        FoodItem(name: "Bhel puri", serving: "1 plate", kcal: 250),
        FoodItem(name: "Dhokla", serving: "2 pieces", kcal: 150),
        FoodItem(name: "Roasted peanuts", serving: "1 handful", kcal: 170),
        FoodItem(name: "Almonds", serving: "10", kcal: 70),
        FoodItem(name: "Biscuits", serving: "2", kcal: 90),
        // Fruit and salad
        FoodItem(name: "Banana", serving: "1 medium", kcal: 105),
        FoodItem(name: "Apple", serving: "1 medium", kcal: 95),
        FoodItem(name: "Mango", serving: "1 cup", kcal: 100),
        FoodItem(name: "Orange", serving: "1", kcal: 60),
        FoodItem(name: "Papaya", serving: "1 cup", kcal: 60),
        FoodItem(name: "Guava", serving: "1", kcal: 70),
        FoodItem(name: "Green salad", serving: "1 bowl", kcal: 30),
        // Sweets
        FoodItem(name: "Gulab jamun", serving: "1", kcal: 150),
        FoodItem(name: "Jalebi", serving: "2 pieces", kcal: 150),
        FoodItem(name: "Rasgulla", serving: "1", kcal: 120),
        FoodItem(name: "Ladoo", serving: "1", kcal: 180),
        FoodItem(name: "Kheer", serving: "1 small bowl", kcal: 200),
        // Fats
        FoodItem(name: "Ghee", serving: "1 tsp", kcal: 45),
        FoodItem(name: "Butter", serving: "1 tsp", kcal: 35),
        FoodItem(name: "Cooking oil", serving: "1 tsp", kcal: 40),
    ]

    static let international: [FoodItem] = [
        // Breakfast
        FoodItem(name: "Oatmeal", serving: "1 bowl", kcal: 160),
        FoodItem(name: "Toast with butter", serving: "1 slice", kcal: 110),
        FoodItem(name: "Scrambled eggs", serving: "2 eggs", kcal: 200),
        FoodItem(name: "Pancakes", serving: "2 medium", kcal: 180),
        FoodItem(name: "Bagel with cream cheese", serving: "1", kcal: 350),
        FoodItem(name: "Croissant", serving: "1", kcal: 230),
        FoodItem(name: "Yogurt with granola", serving: "1 bowl", kcal: 250),
        FoodItem(name: "Avocado toast", serving: "1 slice", kcal: 200),
        FoodItem(name: "Fruit smoothie", serving: "1 glass", kcal: 200),
        // Meals
        FoodItem(name: "Pizza", serving: "1 slice", kcal: 285),
        FoodItem(name: "Burger", serving: "1", kcal: 500),
        FoodItem(name: "Chicken sandwich", serving: "1", kcal: 400),
        FoodItem(name: "Wrap", serving: "1", kcal: 400),
        FoodItem(name: "Pasta with tomato sauce", serving: "1 plate", kcal: 400),
        FoodItem(name: "Spaghetti bolognese", serving: "1 plate", kcal: 550),
        FoodItem(name: "Mac and cheese", serving: "1 cup", kcal: 400),
        FoodItem(name: "Grilled chicken breast", serving: "150 g", kcal: 250),
        FoodItem(name: "Fried chicken", serving: "2 pieces", kcal: 480),
        FoodItem(name: "Steak", serving: "200 g", kcal: 500),
        FoodItem(name: "Salmon fillet", serving: "150 g", kcal: 300),
        FoodItem(name: "Fish and chips", serving: "1 portion", kcal: 800),
        FoodItem(name: "Fried rice", serving: "1 plate", kcal: 450),
        FoodItem(name: "Noodle stir-fry", serving: "1 plate", kcal: 450),
        FoodItem(name: "Ramen", serving: "1 bowl", kcal: 450),
        FoodItem(name: "Sushi", serving: "6 pieces", kcal: 300),
        FoodItem(name: "Dumplings", serving: "6", kcal: 300),
        FoodItem(name: "Tacos", serving: "2", kcal: 350),
        FoodItem(name: "Burrito", serving: "1", kcal: 600),
        FoodItem(name: "Caesar salad", serving: "1 bowl", kcal: 350),
        FoodItem(name: "Soup", serving: "1 bowl", kcal: 150),
        FoodItem(name: "Hot dog", serving: "1", kcal: 300),
        // Sides and snacks
        FoodItem(name: "French fries", serving: "1 medium", kcal: 360, cuisine: .international),
        FoodItem(name: "Potato chips", serving: "1 small bag", kcal: 160),
        FoodItem(name: "Popcorn", serving: "1 bowl", kcal: 100),
        FoodItem(name: "Granola bar", serving: "1", kcal: 190),
        FoodItem(name: "Cheese", serving: "1 slice", kcal: 110),
        FoodItem(name: "Hummus with vegetables", serving: "1 small bowl", kcal: 150),
        FoodItem(name: "Mixed nuts", serving: "1 handful", kcal: 170),
        // Drinks
        FoodItem(name: "Latte", serving: "1 cup", kcal: 190),
        FoodItem(name: "Black coffee", serving: "1 cup", kcal: 5),
        FoodItem(name: "Orange juice", serving: "1 glass", kcal: 110),
        FoodItem(name: "Milkshake", serving: "1 glass", kcal: 400),
        FoodItem(name: "Protein shake", serving: "1", kcal: 150),
        // Sweets
        FoodItem(name: "Ice cream", serving: "1 scoop", kcal: 140),
        FoodItem(name: "Chocolate bar", serving: "1", kcal: 230),
        FoodItem(name: "Cookie", serving: "1 large", kcal: 200),
        FoodItem(name: "Donut", serving: "1", kcal: 250),
        FoodItem(name: "Cake", serving: "1 slice", kcal: 350),
        FoodItem(name: "Muffin", serving: "1", kcal: 400),
        // Fruit
        FoodItem(name: "Grapes", serving: "1 cup", kcal: 100),
        FoodItem(name: "Strawberries", serving: "1 cup", kcal: 50),
        FoodItem(name: "Blueberries", serving: "1 cup", kcal: 85),
        FoodItem(name: "Watermelon", serving: "1 cup", kcal: 45),
        FoodItem(name: "Pineapple", serving: "1 cup", kcal: 80),
        FoodItem(name: "Pear", serving: "1 medium", kcal: 100),
    ].map { FoodItem(name: $0.name, serving: $0.serving, kcal: $0.kcal, cuisine: .international) }

    static func search(_ text: String) -> [FoodItem] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { $0.name.lowercased().contains(query) }
    }
}
