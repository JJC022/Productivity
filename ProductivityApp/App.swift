import SwiftUI

@main
struct ProductivityApp: App {
    @StateObject private var reminderController = ReminderController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(reminderController)
                .onAppear {
                    reminderController.requestAuthorization()
                }
        }
    }
}
