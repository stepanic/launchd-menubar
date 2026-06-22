import SwiftUI

@main
struct LaunchdBarApp: App {
    @StateObject private var store = JobStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            Image(systemName: "timer")
        }
        .menuBarExtraStyle(.window)
    }
}
