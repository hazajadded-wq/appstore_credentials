import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    print("🚀 SalaryInfo App Starting - iOS Notifications Enabled")

    // 🔥 Configure Firebase FIRST
    FirebaseApp.configure()
    print("✅ Firebase configured")

    // 🔔 Notification center delegate
    UNUserNotificationCenter.current().delegate = self

    // 🔥 REQUEST PERMISSION (THIS WAS MISSING ❌)
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    ) { granted, error in
      if let error = error {
        print("❌ Notification permission error: \(error.localizedDescription)")
      } else {
        print("✅ Notification permission granted: \(granted)")
      }
    }

    // 🔔 Register for APNs
    application.registerForRemoteNotifications()
    print("✅ Registered for remote notifications")

    // 🔥 Firebase Messaging delegate
    Messaging.messaging().delegate = self

    // 🔧 Flutter plugins
    GeneratedPluginRegistrant.register(with: self)
    print("✅ Flutter plugins registered")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ============================
  // APNs Token
  // ============================
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken

    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()
    print("✅ APNs device token: \(token)")
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ Failed to register APNs: \(error.localizedDescription)")
  }

  // ============================
  // FOREGROUND notification
  // ============================
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    print("📬 Notification received in foreground")
    completionHandler([.banner, .sound, .badge])
  }

  // ============================
  // Notification tap
  // ============================
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    print("👆 Notification tapped")
    completionHandler()
  }

  // ============================
  // FCM TOKEN
  // ============================
  func messaging(
    _ messaging: Messaging,
    didReceiveRegistrationToken fcmToken: String?
  ) {
    guard let token = fcmToken else {
      print("❌ FCM token is nil")
      return
    }

    print("✅ FCM token: \(token)")

    // 🔥 Subscribe to topic
    Messaging.messaging().subscribe(toTopic: "all_employees") { error in
      if let error = error {
        print("❌ Topic subscribe error: \(error.localizedDescription)")
      } else {
        print("✅ Subscribed to topic all_employees")
      }
    }
  }
}
