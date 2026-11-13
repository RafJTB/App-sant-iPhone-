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
        .liquidGlassTabBar()
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

extension View {
    /// iOS 26+ : la barre d'onglets (Liquid Glass, automatique avec Xcode 26) se réduit
    /// quand on fait défiler vers le bas, comme dans les apps Apple.
    @ViewBuilder
    func liquidGlassTabBar() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
