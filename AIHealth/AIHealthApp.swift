import SwiftUI

@main
struct AIHealthApp: App {
    @StateObject private var healthManager = HealthKitManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthManager)
        }
    }
}
