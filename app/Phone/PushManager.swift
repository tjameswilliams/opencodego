import CloudKit
import SwiftUI
import UserNotifications

/// The phone's half of the no-relay push path: register with APNs (CloudKit
/// routes the actual delivery), keep the CKQuerySubscription in place, and
/// turn a tapped notification into "what needs me, and where".
final class PushManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate,
    ObservableObject {
    /// Set when the user tapped a notification; RootView presents the
    /// approvals flow for it and clears it.
    @Published var attention: Attention.Info?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Called once pairing exists — an unpaired phone has nothing to be
    /// notified about, and asking for permission before the app has proven
    /// useful is how prompts get declined.
    func enable() {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )) ?? false
            guard granted else { return }
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            await Attention.ensureSubscription()
        }
    }

    /// Alert pushes while the app is frontmost: show them anyway — the user
    /// may be on the Home screen while a turn runs in another session.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// The tap: resolve the record the push named, then hand the result to
    /// the UI. The push itself carried no content — this fetch is where the
    /// phone learns what actually happened.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let info = await Attention.resolve(userInfo: userInfo) else { return }
        await MainActor.run { attention = info }
    }
}
