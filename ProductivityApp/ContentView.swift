import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: ReminderController
    @State private var previewReminder: ReminderType = .exercise
    @State private var focusDurationMinutes = 15
    @State private var blockedAppsText = "com.instagram.ios, com.facebook.Facebook"

    var body: some View {
        NavigationStack {
            Form {
                Section("Focus cadence") {
                    Toggle("Enable reminders", isOn: $controller.settings.enabled)
                    Stepper("Every \(controller.settings.intervalMinutes) min", value: $controller.settings.intervalMinutes, in: 15...90, step: 5)
                    Button("Save and schedule reminders") {
                        controller.scheduleReminders()
                    }
                    .disabled(!controller.settings.enabled)
                }

                Section("Reminder types") {
                    ForEach(ReminderType.allCases) { reminder in
                        Toggle(reminder.title, isOn: Binding(
                            get: { controller.settings.selectedReminders.contains(reminder) },
                            set: { enabled in
                                if enabled {
                                    controller.settings.selectedReminders.insert(reminder)
                                } else {
                                    controller.settings.selectedReminders.remove(reminder)
                                }
                                controller.scheduleReminders()
                            }
                        ))
                    }
                }

                Section("Quick start") {
                    Button("Start a 5-minute focus block") {
                        controller.beginFocusBlock(durationSeconds: 300)
                    }

                    Picker("Preview reminder", selection: $previewReminder) {
                        ForEach(ReminderType.allCases) { reminder in
                            Text(reminder.title).tag(reminder)
                        }
                    }

                    Button("Show preview reminder") {
                        controller.showImmediateReminder(for: previewReminder)
                    }
                }

                Section("Focus mode") {
                    Toggle("Enable configurable blocking", isOn: $controller.focusModeSettings.enabled)
                    Stepper("Duration: \(focusDurationMinutes) min", value: $focusDurationMinutes, in: 5...60, step: 5)
                    TextField("Bundle IDs to block", text: $blockedAppsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Start focus session") {
                        controller.startFocusSession(durationMinutes: focusDurationMinutes, blockedBundleIDs: blockedAppsText.components(separatedBy: ","))
                        controller.saveSettings()
                    }
                    .disabled(!controller.focusModeSettings.enabled)

                    if controller.focusModeActive {
                        Text(controller.focusModeMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Status") {
                    if controller.isPermissionGranted {
                        Label("Notifications are ready", systemImage: "bell.badge.fill")
                    } else {
                        Label("Notifications need permission", systemImage: "bell.slash")
                    }

                    if controller.focusTimerActive {
                        Label("Focus block: \(controller.formattedRemainingTime)", systemImage: "clock")
                    }

                    Text(controller.activeReminder?.title ?? "No active reminder")
                }
            }
            .navigationTitle("Productivity")
            .fullScreenCover(item: $controller.activeReminder) { reminder in
                ReminderOverlay(reminder: reminder, controller: controller)
            }
        }
    }
}

struct ReminderOverlay: View {
    let reminder: ReminderType
    @ObservedObject var controller: ReminderController

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                Text(reminder.title)
                    .font(.largeTitle.weight(.bold))

                Text(reminder.bodyText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if controller.focusTimerActive {
                    Text(controller.formattedRemainingTime)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                HStack(spacing: 16) {
                    Button("Start 5 min") {
                        controller.beginFocusBlock(durationSeconds: 300)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Snooze 5 min") {
                        controller.snoozeCurrentReminder()
                    }
                    .buttonStyle(.bordered)

                    Button("Done") {
                        controller.completeCurrentReminder()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ReminderController())
}
