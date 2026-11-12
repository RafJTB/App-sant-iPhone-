import Foundation

/// Un aliment de référence. `base` = valeurs pour 100 g, ou pour 1 portion si `isPortion`.
struct FoodItem: Identifiable, Hashable {
    let id: String
    let name: String
    let base: Macros
    let isPortion: Bool
    let defaultAmount: Double

    func macros(for amount: Double) -> Macros {
        base * (isPortion ? amount : amount / 100)
    }

    static func == (lhs: FoodItem, rhs: FoodItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Petite base d'aliments courants. Valeurs moyennes approximatives pour 100 g
/// (ordre de grandeur des tables CIQUAL / étiquettes). À affiner selon tes produits.
enum FoodDatabase {
    private static func item(_ name: String, _ kcal: Double, _ p: Double, _ c: Double, _ f: Double, portion: Double) -> FoodItem {
        FoodItem(id: "db-\(name)", name: name,
                 base: Macros(kcal: kcal, protein: p, carbs: c, fat: f),
                 isPortion: false, defaultAmount: portion)
    }

    static let items: [FoodItem] = [
        // Féculents
        item("Riz blanc cuit", 130, 2.7, 28, 0.3, portion: 200),
        item("Pâtes cuites", 150, 5.5, 30, 0.9, portion: 250),
        item("Semoule / couscous cuit", 115, 4, 23, 0.2, portion: 200),
        item("Quinoa cuit", 120, 4.4, 21, 1.9, portion: 180),
        item("Pomme de terre cuite", 85, 2, 18, 0.1, portion: 200),
        item("Patate douce cuite", 90, 2, 20, 0.2, portion: 200),
        item("Pain baguette", 270, 9, 55, 1.5, portion: 60),
        item("Pain complet", 240, 9, 44, 3, portion: 50),
        item("Flocons d'avoine", 370, 13, 60, 7, portion: 60),
        item("Céréales petit-déjeuner", 380, 8, 78, 3, portion: 40),
        item("Lentilles cuites", 115, 9, 17, 0.4, portion: 200),
        item("Pois chiches cuits", 140, 8, 19, 2.5, portion: 150),
        // Protéines
        item("Blanc de poulet cuit", 165, 31, 0, 3.6, portion: 150),
        item("Steak haché 5 % cuit", 155, 26, 0, 5.5, portion: 125),
        item("Steak haché 15 % cuit", 250, 24, 0, 17, portion: 125),
        item("Saumon cuit", 200, 22, 0, 12, portion: 130),
        item("Thon au naturel", 115, 26, 0, 1, portion: 100),
        item("Jambon blanc", 115, 20, 1, 3.5, portion: 40),
        item("Œuf entier", 140, 12.5, 0.5, 10, portion: 50),
        item("Tofu", 125, 13, 2, 7.5, portion: 100),
        item("Whey protéine (poudre)", 380, 78, 6, 5, portion: 30),
        // Produits laitiers
        item("Lait demi-écrémé", 46, 3.3, 4.8, 1.6, portion: 250),
        item("Yaourt nature", 60, 4, 5, 3, portion: 125),
        item("Skyr / fromage blanc 0 %", 60, 10, 4, 0.2, portion: 150),
        item("Fromage blanc 3 %", 85, 7.5, 4, 3.5, portion: 100),
        item("Emmental", 380, 28, 0, 30, portion: 30),
        item("Camembert", 270, 20, 0.5, 21, portion: 30),
        // Matières grasses / oléagineux
        item("Beurre", 740, 0.7, 0.6, 82, portion: 10),
        item("Huile d'olive", 900, 0, 0, 100, portion: 10),
        item("Beurre de cacahuète", 600, 25, 15, 50, portion: 30),
        item("Amandes", 600, 21, 9, 52, portion: 30),
        item("Noix", 680, 15, 7, 65, portion: 30),
        item("Avocat", 160, 2, 2, 15, portion: 100),
        // Fruits & légumes
        item("Banane", 90, 1.1, 20, 0.3, portion: 120),
        item("Pomme", 53, 0.3, 11.5, 0.2, portion: 150),
        item("Orange", 47, 0.9, 9, 0.1, portion: 150),
        item("Fruits rouges", 45, 1, 7, 0.4, portion: 100),
        item("Dattes", 280, 2.5, 66, 0.4, portion: 30),
        item("Brocoli cuit", 35, 2.5, 4, 0.4, portion: 150),
        item("Haricots verts cuits", 30, 2, 4, 0.2, portion: 150),
        item("Carottes", 35, 0.8, 7, 0.2, portion: 100),
        item("Tomate", 18, 0.9, 3, 0.2, portion: 120),
        item("Salade verte", 15, 1.3, 1.5, 0.2, portion: 50),
        // Sucré / boissons
        item("Croissant", 410, 8, 45, 21, portion: 60),
        item("Biscuits", 470, 6.5, 70, 18, portion: 30),
        item("Chocolat noir 70 %", 580, 8, 33, 42, portion: 20),
        item("Miel", 320, 0.4, 80, 0, portion: 20),
        item("Confiture", 250, 0.4, 60, 0.1, portion: 20),
        item("Jus d'orange", 45, 0.7, 10, 0.1, portion: 250),
        item("Soda sucré", 42, 0, 10.6, 0, portion: 330),
        item("Bière", 43, 0.4, 3.5, 0, portion: 250),
        // Plats
        item("Pizza", 260, 11, 30, 10, portion: 300),
        item("Burger (fast-food)", 260, 13, 26, 11, portion: 220),
        item("Frites", 300, 3.5, 37, 15, portion: 150),
        item("Kebab (sandwich)", 230, 12, 22, 10, portion: 350),
    ]
}
