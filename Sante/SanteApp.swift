import SwiftUI
import SwiftData

@main
struct SanteApp: App {
    @StateObject private var health = HealthDataStore()
    @StateObject private var profile = ProfileStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(health)
                .environmentObject(profile)
        }
        .modelContainer(for: FoodEntry.self)
    }
}
