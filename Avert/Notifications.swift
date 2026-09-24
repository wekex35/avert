import Foundation
import UserNotifications

extension Notification.Name {
    static let avertOpenMainWindow = Notification.Name("avertOpenMainWindow")
    static let avertOpenNeckExercises = Notification.Name("avertOpenNeckExercises")
    static let avertShowAbout = Notification.Name("avertShowAbout")
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private(set) var authorizationGranted = false

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async {
        do {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                authorizationGranted = true
            case .notDetermined:
                authorizationGranted = try await center.requestAuthorization(options: [.alert, .sound])
            default:
                authorizationGranted = false
            }
        } catch {
            authorizationGranted = false
        }

        registerCategories()
    }

    private func registerCategories() {
        let open = UNNotificationAction(
            identifier: NeckExerciseNotification.actionOpen,
            title: "Start exercises",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: NeckExerciseNotification.categoryID,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func postNeckCare(_ event: NeckCareEvent) {
        guard authorizationGranted else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        switch event {
        case .stillness:
            content.title = "Time for a neck break"
            content.body = "You’ve been still while looking at the screen. Glance away, roll your shoulders, or stand for a moment."
        case .sustainedFlex:
            content.title = "Ease your neck"
            content.body = "Your head has stayed tilted for a while. Lift your gaze and gently reset your posture."
        }

        let request = UNNotificationRequest(
            identifier: "avert.neckcare.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func postRecalibratePrompt() {
        guard authorizationGranted else { return }
        let content = UNMutableNotificationContent()
        content.title = "Recalibrate Avert"
        content.body = "Your head pose drifted after a posture change. Open Avert and calibrate while facing the screen."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "avert.recalibrate.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    /// Schedule a repeating 2-hour reminder to complete the neck set once.
    func scheduleNeckExerciseReminders(enabled: Bool) {
        center.removePendingNotificationRequests(withIdentifiers: [NeckExerciseNotification.requestID])
        guard enabled, authorizationGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Neck mobility set"
        content.body = "Look, tilt, turn — slow holds (not bouncing). Do the routine once: center 2–3s, stretch 15–20s (look-up shorter)."
        content.sound = .default
        content.categoryIdentifier = NeckExerciseNotification.categoryID
        content.userInfo = [NeckExerciseNotification.userInfoKey: NeckExerciseNotification.userInfoOpen]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2 * 60 * 60, repeats: true)
        let request = UNNotificationRequest(
            identifier: NeckExerciseNotification.requestID,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let action = info[NeckExerciseNotification.userInfoKey] as? String
        let openExercises = action == NeckExerciseNotification.userInfoOpen
            || response.actionIdentifier == NeckExerciseNotification.actionOpen
            || response.notification.request.identifier == NeckExerciseNotification.requestID

        if openExercises {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .avertOpenNeckExercises, object: nil)
            }
        }
        completionHandler()
    }
}
