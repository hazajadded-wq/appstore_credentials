import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    print("🚀 SalaryInfo App Starting - iOS Notifications Enabled")

    // Firebase init (safe)
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
      print("✅ Firebase configured")
    }

    // Notification center delegate
    UNUserNotificationCenter.current().delegate = self

    // Register for APNs
    application.registerForRemoteNotifications()
    print("✅ Registered for remote notifications")

    // Flutter plugins
    GeneratedPluginRegistrant.register(with: self)

    // Firebase Messaging delegate
    Messaging.messaging().delegate = self
    print("✅ Firebase Messaging delegate set")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - APNs token

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken

    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("✅ APNs token: \(token)")
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ Failed to register for notifications: \(error.localizedDescription)")
  }

  // MARK: - Foreground notification

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {

    print("📬 Notification received in foreground:")
    print(notification.request.content.userInfo)

    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  // MARK: - Notification tap

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {

    print("👆 User tapped notification:")
    print(response.notification.request.content.userInfo)

    completionHandler()
  }
}

// MARK: - Firebase Messaging
extension AppDelegate: MessagingDelegate {

  func messaging(
    _ messaging: Messaging,
    didReceiveRegistrationToken fcmToken: String?
  ) {

    guard let token = fcmToken else {
      print("❌ FCM token is nil")
      return
    }

    print("✅ FCM token received: \(token)")

    // Auto subscribe
    Messaging.messaging().subscribe(toTopic: "all_employees") { error in
      if let error = error {
        print("❌ Topic subscribe failed: \(error.localizedDescription)")
      } else {
        print("✅ Subscribed to topic: all_employees")
      }
    }

    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: ["token": token]
    )
  }
}
