import SwiftUI

@main
struct ArcadePadApp: App {
    @StateObject private var kitStore = KitStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(kitStore)
                .preferredColorScheme(.dark)
        }
    }
}
