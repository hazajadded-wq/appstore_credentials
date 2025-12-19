import UIKit
import Flutter
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

    // ✅ إعداد Notifications فقط (بدون Firebase!)
    // Firebase سيتم تهيئته من Flutter في main.dart
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    print("✅ Notifications configured")

    // ✅ تسجيل Flutter Plugins
    GeneratedPluginRegistrant.register(with: self)
    print("✅ Flutter plugins registered")

    // ❗ مهم جدًا: return true
    // Flutter سيهيّئ Firebase من main.dart
    print("✅ AppDelegate finished - Flutter will initialize Firebase")
    return true
  }

  // MARK: - APNs Token Handling
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("✅ APNs device token received: \(tokenString.prefix(20))...")
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
    let userInfo = notification.request.content.userInfo
    print("📱 Notification received (foreground): \(userInfo)")
    
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
    let userInfo = response.notification.request.content.userInfo
    print("📱 Notification tapped: \(userInfo)")
    completionHandler()
  }
}