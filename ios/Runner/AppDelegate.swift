import UIKit
import Flutter
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    print("🚀 SalaryInfo App Started")

    // ❌ لا تستدعي FirebaseApp.configure()
    // FlutterFire يقوم بها تلقائياً

    // ✅ CRITICAL: Set delegate BEFORE registering plugins
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)

    // ✅ CRITICAL: Set delegate AGAIN AFTER plugins to ensure it's not overridden
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    Messaging.messaging().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - APNs token
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    print("✅ APNs token set: \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined().prefix(20))...")
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ APNs registration failed: \(error.localizedDescription)")
  }

  // MARK: - Foreground notification (THIS IS THE KEY!)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    print("📱 willPresent called - App is in FOREGROUND")
    print("📱 Notification title: \(notification.request.content.title)")
    print("📱 Notification body: \(notification.request.content.body)")
    
    // ✅ CRITICAL: Show banner/alert even when app is open
    if #available(iOS 14.0, *) {
      // iOS 14+: Use .banner
      completionHandler([.banner, .sound, .badge])
      print("✅ Showing notification with banner (iOS 14+)")
    } else {
      // iOS 13 and below: Use .alert
      completionHandler([.alert, .sound, .badge])
      print("✅ Showing notification with alert (iOS 13)")
    }
  }

  // MARK: - Notification tap
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    print("👆 User tapped notification")
    print("📱 Action: \(response.actionIdentifier)")
    completionHandler()
  }
}

// MARK: - Firebase Messaging
extension AppDelegate: MessagingDelegate {

  func messaging(
    _ messaging: Messaging,
    didReceiveRegistrationToken fcmToken: String?
  ) {
    guard let token = fcmToken else { return }
    print("✅ FCM token received")
    print("✅ Token (first 30 chars): \(String(token.prefix(30)))...")
  }
}