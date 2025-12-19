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

    print("""
    ================================
    🚀 SalaryInfo App Starting
    Bundle ID: com.pocket.salaryinfo
    Firebase: Waiting for Flutter init
    ================================
    """)

    // ✅ 1. إعداد Notification Center
    UNUserNotificationCenter.current().delegate = self
    
    // ✅ 2. تسجيل للحصول على APNs token
    application.registerForRemoteNotifications()
    print("✅ Registered for remote notifications")

    // ✅ 3. تسجيل Flutter Plugins
    GeneratedPluginRegistrant.register(with: self)
    print("✅ Flutter plugins registered")

    // ✅ 4. إعداد Firebase Messaging delegate
    // سيعمل بعد أن Flutter يهيّئ Firebase
    Messaging.messaging().delegate = self
    print("✅ Firebase Messaging delegate set")

    // ❗ مهم: بدون Firebase.configure()!
    // Flutter سيهيّئ Firebase من main.dart
    
    print("✅ AppDelegate setup complete")
    return true
  }

  // MARK: - APNs Token Handling
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("✅ APNs device token received: \(tokenString.prefix(20))...")

    // ✅ CRITICAL: إرسال APNs token إلى Firebase Messaging
    Messaging.messaging().apnsToken = deviceToken
    print("✅ APNs token sent to Firebase Messaging")
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
    print("📱 Notification received (foreground):")
    print("   Title: \(notification.request.content.title)")
    print("   Body: \(notification.request.content.body)")
    print("   Data: \(userInfo)")
    
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
    print("📱 Notification tapped:")
    print("   Data: \(userInfo)")
    completionHandler()
  }

  // MARK: - Handle Background/Silent Notifications
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    print("📱 Background notification received: \(userInfo)")
    
    // معالجة الإشعار الصامت
    if let aps = userInfo["aps"] as? [String: Any],
       let contentAvailable = aps["content-available"] as? Int,
       contentAvailable == 1 {
      print("   Silent notification detected")
    }
    
    completionHandler(.newData)
  }
}

// MARK: - Firebase Messaging Delegate
extension AppDelegate: MessagingDelegate {
  
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let token = fcmToken else {
      print("❌ No FCM token received")
      return
    }
    
    print("✅ FCM Token received: \(token.prefix(20))...")
    print("   Full token: \(token)")
    
    // حفظ التوكن في UserDefaults
    UserDefaults.standard.set(token, forKey: "fcm_token")
    
    // إرسال التوكن إلى السيرفر (اختياري)
    // sendTokenToServer(token)
    
    // الاشتراك في topic للإشعارات الجماعية
    Messaging.messaging().subscribe(toTopic: "all_employees") { error in
      if let error = error {
        print("❌ Failed to subscribe to topic: \(error.localizedDescription)")
      } else {
        print("✅ Successfully subscribed to topic: all_employees")
      }
    }
  }
  
  // يُستدعى عندما يتم حذف FCM token
  func messaging(_ messaging: Messaging, didDeleteFCMToken fcmToken: String) {
    print("⚠️ FCM token deleted: \(fcmToken.prefix(20))...")
  }
}