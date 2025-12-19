import UIKit
import Flutter
import Firebase
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    print("""
    ================================
    🚀 SalaryInfo App Starting
    Bundle ID: com.pocket.salaryinfo
    ================================
    """)

    // ✅ 1. تهيئة Firebase بأمان (بدون كراش)
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
      print("✅ Firebase configured")
    } else {
      print("ℹ️ Firebase already initialized")
    }

    // ✅ 2. إعداد Notifications
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    print("✅ Notifications configured")

    // ✅ 3. تسجيل Flutter Plugins
    GeneratedPluginRegistrant.register(with: self)
    print("✅ Flutter plugins registered")

    // ❗ مهم جدًا: return true (وليس return super)
    return true
  }

  // MARK: - APNs Token Handling
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    print("✅ APNs device token received")
    // يمكنك إضافة كود إضافي هنا إذا احتجت
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ APNs registration failed: \(error.localizedDescription)")
  }

  // MARK: - Notification Handling (Foreground)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    print("📱 Notification received (foreground)")
    
    // عرض الإشعار حتى لو التطبيق مفتوح
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    print("📱 Notification tapped")
    completionHandler()
  }
}