import SwiftUI

@main
struct BSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            Color.clear.frame(width: 0, height: 0)
                .hidden()
        }
    }
}
