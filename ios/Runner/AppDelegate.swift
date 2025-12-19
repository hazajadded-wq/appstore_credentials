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

    // Setup Notification Center
    UNUserNotificationCenter.current().delegate = self
    
    // Register for remote notifications
    application.registerForRemoteNotifications()
    print("✅ Registered for remote notifications")

    // Register Flutter Plugins
    GeneratedPluginRegistrant.register(with: self)
    print("✅ Flutter plugins registered")

    // Setup Firebase Messaging delegate
    Messaging.messaging().delegate = self
    print("✅ Firebase Messaging delegate set")
    
    print("✅ AppDelegate setup complete")
    return true
  }

  // APNs Token Handler
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()
    print("✅ APNs device token: \(token)")
    
    // Link APNs token with Firebase
    Messaging.messaging().apnsToken = deviceToken
    print("✅ APNs token sent to Firebase Messaging")
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ Failed to register: \(error.localizedDescription)")
  }

  // Show notification in foreground
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    print("📬 Notification received in foreground:")
    print(userInfo)
    
    if #available(iOS 14.0, *) {
      completionHandler([[.banner, .sound, .badge]])
    } else {
      completionHandler([[.alert, .sound, .badge]])
    }
  }

  // Handle notification tap
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    print("👆 User tapped notification:")
    print(userInfo)
    
    completionHandler()
  }
}

// Firebase Messaging Delegate
extension AppDelegate: MessagingDelegate {
  func messaging(
    _ messaging: Messaging,
    didReceiveRegistrationToken fcmToken: String?
  ) {
    guard let fcmToken = fcmToken else {
      print("❌ FCM token is nil")
      return
    }
    
    print("✅ FCM Token received: \(fcmToken)")
    
    // Subscribe to topic automatically
    Messaging.messaging().subscribe(toTopic: "all_employees") { error in
      if let error = error {
        print("❌ Failed to subscribe: \(error.localizedDescription)")
      } else {
        print("✅ Subscribed to topic: all_employees")
      }
    }
    
    let dataDict: [String: String] = ["token": fcmToken]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: dataDict
    )
  }
}