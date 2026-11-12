// Vérifie le client Open Food Facts contre l'API réelle (lancé par la CI sur macOS).
import Foundation

func check() async -> Bool {
    var ok = true
    let client = OpenFoodFactsClient.shared
    do {
        let p = try await client.product(barcode: "3017620422003") // Nutella 400 g
        print("✅ Code-barres : \(p.displayName) — \(Int(p.per100g.kcal)) kcal/100 g, P \(p.per100g.protein) G \(p.per100g.carbs) L \(p.per100g.fat), portion \(p.servingGrams.map { "\($0) g" } ?? "?")")
        if p.per100g.kcal < 400 || p.per100g.kcal > 600 { print("❌ kcal incohérentes"); ok = false }
    } catch {
        print("❌ Code-barres : \(error)"); ok = false
    }
    do {
        _ = try await client.product(barcode: "0000000000000")
        print("❌ Un code inexistant aurait dû échouer"); ok = false
    } catch {
        print("✅ Code inexistant : \(error.localizedDescription)")
    }
    do {
        let results = try await client.search("skyr")
        print("✅ Recherche « skyr » : \(results.count) résultats")
        for r in results.prefix(5) { print("   • \(r.displayName) — \(Int(r.per100g.kcal)) kcal, P \(r.per100g.protein) g") }
        if results.isEmpty { ok = false }
    } catch {
        print("⚠️ Recherche : \(error) (l'API de recherche est parfois limitée/lente)")
    }
    return ok
}

let semaphore = DispatchSemaphore(value: 0)
var success = false
Task { success = await check(); semaphore.signal() }
semaphore.wait()
exit(success ? 0 : 1)
