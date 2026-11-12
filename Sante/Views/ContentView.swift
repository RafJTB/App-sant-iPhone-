import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var health: HealthDataStore
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Aujourd'hui", systemImage: "chart.line.uptrend.xyaxis") }
            FoodLogView()
                .tabItem { Label("Repas", systemImage: "fork.knife") }
            SleepView()
                .tabItem { Label("Sommeil", systemImage: "bed.double.fill") }
            ActivityView()
                .tabItem { Label("Sport", systemImage: "figure.run") }
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
        }
        .task {
            await health.requestAuthorizationAndLoad()
            if !profile.didImportFromHealth {
                profile.importFromHealth(health)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await health.reload() }
            }
        }
    }
}
