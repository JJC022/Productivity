import Foundation
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let reminderActivated = Notification.Name("reminderActivated")
}

enum ReminderType: String, CaseIterable, Identifiable, Codable, Hashable {
    case exercise
    case eyes
    case journal
    case planNextTask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exercise:
            return "Exercise"
        case .eyes:
            return "Eye relief"
        case .journal:
            return "Journal"
        case .planNextTask:
            return "Plan next task"
        }
    }

    var bodyText: String {
        switch self {
        case .exercise:
            return "Take a short movement break and stretch your body."
        case .eyes:
            return "Look away from the screen, relax your face, and blink slowly for 30 seconds."
        case .journal:
            return "Write a quick note about what you just finished and how it felt."
        case .planNextTask:
            return "Choose the next task and set one clear intention before you continue."
        }
    }
}

struct ReminderSettings: Codable {
    var intervalMinutes: Int = 45
    var enabled: Bool = true
    var selectedReminders: Set<ReminderType> = [.exercise, .eyes, .journal, .planNextTask]
}

struct FocusModeSettings: Codable {
    var enabled: Bool = false
    var durationMinutes: Int = 15
    var blockedAppBundleIDs: [String] = ["com.instagram.ios", "com.facebook.Facebook"]
    var showBlockingOverlay: Bool = true
}

final class ReminderController: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var settings = ReminderSettings()
    @Published var focusModeSettings = FocusModeSettings()
    @Published var activeReminder: ReminderType?
    @Published var isPermissionGranted = false
    @Published var focusRemainingSeconds = 0
    @Published var focusTimerActive = false
    @Published var focusModeActive = false
    @Published var focusModeMessage = ""

    private var focusTimer: Timer?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReminderActivation(_:)),
            name: .reminderActivated,
            object: nil
        )
        loadSettings()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        focusTimer?.invalidate()
    }

    var formattedRemainingTime: String {
        let minutes = focusRemainingSeconds / 60
        let seconds = focusRemainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.isPermissionGranted = granted
                if granted {
                    self.scheduleReminders()
                }
            }
        }
    }

    func saveSettings() {
        let encoder = JSONEncoder()
        if let reminderData = try? encoder.encode(settings) {
            UserDefaults.standard.set(reminderData, forKey: "Productivity.ReminderSettings")
        }
        if let focusData = try? encoder.encode(focusModeSettings) {
            UserDefaults.standard.set(focusData, forKey: "Productivity.FocusModeSettings")
        }
    }

    func loadSettings() {
        let decoder = JSONDecoder()
        if let reminderData = UserDefaults.standard.data(forKey: "Productivity.ReminderSettings"),
           let decoded = try? decoder.decode(ReminderSettings.self, from: reminderData) {
            settings = decoded
        }
        if let focusData = UserDefaults.standard.data(forKey: "Productivity.FocusModeSettings"),
           let decoded = try? decoder.decode(FocusModeSettings.self, from: focusData) {
            focusModeSettings = decoded
        }
    }

    func scheduleReminders() {
        saveSettings()

        guard settings.enabled else {
            cancelAllPendingReminders()
            return
        }

        cancelAllPendingReminders()

        for reminder in settings.selectedReminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.bodyText
            content.sound = .default
            content.categoryIdentifier = "productivityReminder"

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(settings.intervalMinutes * 60),
                repeats: true
            )

            let request = UNNotificationRequest(
                identifier: reminder.rawValue,
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request)
        }
    }

    func showImmediateReminder(for reminder: ReminderType) {
        activeReminder = reminder
        focusModeActive = false
        focusModeMessage = ""
        beginFocusBlock(durationSeconds: 300)
    }

    func beginFocusBlock(durationSeconds: Int = 300) {
        focusTimer?.invalidate()
        focusRemainingSeconds = durationSeconds
        focusTimerActive = true

        focusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.focusRemainingSeconds > 0 {
                self.focusRemainingSeconds -= 1
            } else {
                self.stopFocusSession()
            }
        }
    }

    func stopFocusSession() {
        focusTimer?.invalidate()
        focusTimer = nil
        focusTimerActive = false
        focusRemainingSeconds = 0
        focusModeActive = false
        focusModeMessage = ""
        activeReminder = nil
    }

    func completeCurrentReminder() {
        stopFocusSession()
    }

    func snoozeCurrentReminder() {
        guard let reminder = activeReminder else { return }

        let content = UNMutableNotificationContent()
        content.title = "Snoozed: \(reminder.title)"
        content.body = reminder.bodyText
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(reminder.rawValue)-snooze",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
        activeReminder = nil
        stopFocusSession()
    }

    func updateBlockedAppList(_ input: String) {
        let cleaned = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        focusModeSettings.blockedAppBundleIDs = cleaned
        saveSettings()
    }

    func startFocusSession(durationMinutes: Int, blockedBundleIDs: [String]) {
        focusModeSettings.durationMinutes = max(5, durationMinutes)
        focusModeSettings.blockedAppBundleIDs = blockedBundleIDs.filter { !$0.isEmpty }
        focusModeSettings.enabled = true
        saveSettings()

        let blockedSummary = focusModeSettings.blockedAppBundleIDs.isEmpty ? "your selected apps" : focusModeSettings.blockedAppBundleIDs.joined(separator: ", ")
        focusModeMessage = "Stay on task and avoid opening: \(blockedSummary)."
        focusModeActive = true
        activeReminder = nil
        beginFocusBlock(durationSeconds: focusModeSettings.durationMinutes * 60)

        let content = UNMutableNotificationContent()
        content.title = "Focus mode started"
        content.body = "Your configured focus session is active. Keep away from: \(blockedSummary)."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "focus-mode-start", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelAllPendingReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    @objc
    private func handleReminderActivation(_ notification: Notification) {
        guard let reminder = notification.userInfo?["reminder"] as? ReminderType else { return }
        activeReminder = reminder
        focusModeActive = false
        focusModeMessage = ""
        beginFocusBlock(durationSeconds: 300)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let reminder = ReminderType(rawValue: response.notification.request.identifier)
        if let reminder {
            NotificationCenter.default.post(name: .reminderActivated, object: nil, userInfo: ["reminder": reminder])
        }
        completionHandler()
    }
}
