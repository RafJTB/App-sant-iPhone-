import Foundation

/// Produit trouvé sur Open Food Facts (base collaborative et gratuite, très fournie en produits français).
struct OFFProduct: Identifiable, Hashable {
    let code: String
    let name: String
    let brand: String?
    /// Valeurs pour 100 g (ou 100 ml).
    let per100g: Macros
    /// Taille d'une portion indiquée sur l'emballage, en grammes.
    let servingGrams: Double?

    var id: String { code }

    var displayName: String {
        guard let brand, !brand.isEmpty else { return name }
        return "\(name) – \(brand)"
    }

    var asFoodItem: FoodItem {
        FoodItem(id: "off-\(code)", name: displayName, base: per100g,
                 isPortion: false, defaultAmount: servingGrams ?? 100)
    }

    static func == (lhs: OFFProduct, rhs: OFFProduct) -> Bool { lhs.code == rhs.code }
    func hash(into hasher: inout Hasher) { hasher.combine(code) }
}

enum OFFError: LocalizedError {
    case notFound
    case noNutrition
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Produit introuvable sur Open Food Facts. Tu peux le saisir manuellement à partir de l'étiquette."
        case .noNutrition:
            return "Ce produit existe sur Open Food Facts mais sans valeurs nutritionnelles. Saisis-le manuellement."
        case .network(let message):
            return "Connexion à Open Food Facts impossible (\(message))."
        }
    }
}

/// Client minimal de l'API Open Food Facts (lecture seule, sans compte).
struct OpenFoodFactsClient {
    static let shared = OpenFoodFactsClient()

    /// Open Food Facts demande un User-Agent identifiant l'application.
    private let userAgent = "SanteApp/1.0 (iOS; usage personnel)"
    private let fields = "code,product_name,product_name_fr,brands,nutriments,serving_quantity"
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    /// Recherche par code-barres (EAN-13, EAN-8, UPC).
    func product(barcode: String) async throws -> OFFProduct {
        let code = barcode.filter(\.isNumber)
        guard !code.isEmpty else { throw OFFError.notFound }
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        components.queryItems = [URLQueryItem(name: "fields", value: fields)]
        let data = try await get(components.url!, allowNotFound: true)
        let response = try JSONDecoder().decode(OFFProductResponse.self, from: data)
        guard (response.status?.value ?? 0) == 1, let raw = response.product else { throw OFFError.notFound }
        guard let product = raw.toProduct(fallbackCode: code) else { throw OFFError.noNutrition }
        return product
    }

    /// Recherche texte, limitée aux produits vendus en France.
    func search(_ query: String, limit: Int = 25) async throws -> [OFFProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var components = URLComponents(string: "https://fr.openfoodfacts.org/cgi/search.pl")!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(limit)),
            URLQueryItem(name: "sort_by", value: "unique_scans_n"),
            URLQueryItem(name: "fields", value: fields),
        ]
        let data = try await get(components.url!, allowNotFound: false)
        let response = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        return (response.products ?? []).compactMap { $0.toProduct(fallbackCode: nil) }
    }

    private func get(_ url: URL, allowNotFound: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OFFError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 && allowNotFound { throw OFFError.notFound }
            guard (200..<300).contains(http.statusCode) else {
                throw OFFError.network("code HTTP \(http.statusCode)")
            }
        }
        return data
    }
}

// MARK: - Décodage

/// Open Food Facts renvoie parfois les nombres sous forme de texte : on accepte les deux.
struct FlexibleDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            value = d
        } else if let s = try? container.decode(String.self) {
            value = Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        } else {
            value = nil
        }
    }
}

private struct OFFProductResponse: Decodable {
    let status: FlexibleDouble?
    let product: OFFRawProduct?
}

private struct OFFSearchResponse: Decodable {
    let products: [OFFRawProduct]?
}

private struct OFFRawProduct: Decodable {
    let code: String?
    let product_name: String?
    let product_name_fr: String?
    let brands: String?
    let nutriments: [String: FlexibleDouble]?
    let serving_quantity: FlexibleDouble?

    func nutrient(_ key: String) -> Double? {
        nutriments?["\(key)_100g"]?.value
    }

    func toProduct(fallbackCode: String?) -> OFFProduct? {
        guard let code = code ?? fallbackCode else { return nil }
        let name = [product_name_fr, product_name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let name else { return nil }

        // kcal directement, sinon conversion depuis les kJ
        let kcal = nutrient("energy-kcal") ?? nutrient("energy").map { $0 / 4.184 }
        guard let kcal, kcal >= 0 else { return nil }

        let brand = brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        let serving = serving_quantity?.value.flatMap { $0 > 0 ? $0 : nil }
        return OFFProduct(
            code: code,
            name: name,
            brand: brand,
            per100g: Macros(kcal: kcal,
                            protein: nutrient("proteins") ?? 0,
                            carbs: nutrient("carbohydrates") ?? 0,
                            fat: nutrient("fat") ?? 0),
            servingGrams: serving
        )
    }
}
