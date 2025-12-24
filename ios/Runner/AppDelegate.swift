import UIKit
import Flutter
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  // ✅ CRITICAL: MethodChannel for direct communication with Flutter
  private var notificationChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    print("🚀 SalaryInfo App Started")

    // ❌ لا تستدعي FirebaseApp.configure()
    // FlutterFire يقوم بها تلقائياً

    // ✅ CRITICAL: Set up MethodChannel FIRST
    let controller = window?.rootViewController as! FlutterViewController
    notificationChannel = FlutterMethodChannel(
      name: "com.pocket.salaryinfo/notifications",
      binaryMessenger: controller.binaryMessenger
    )
    print("✅ MethodChannel created: com.pocket.salaryinfo/notifications")

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

  // MARK: - Foreground notification (CRITICAL FIX!)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    print("📱 ========================================")
    print("📱 willPresent called - App is FOREGROUND")
    print("📱 ========================================")
    
    let userInfo = notification.request.content.userInfo
    let title = notification.request.content.title
    let body = notification.request.content.body
    
    print("📱 Notification title: \(title)")
    print("📱 Notification body: \(body)")
    print("📱 userInfo: \(userInfo)")
    
    // ✅ METHOD 1: Send to Flutter via MethodChannel (MOST RELIABLE!)
    sendNotificationToFlutter(
      title: title,
      body: body,
      userInfo: userInfo,
      isForeground: true
    )
    
    // ✅ METHOD 2: Also try Firebase method (backup)
    Messaging.messaging().appDidReceiveMessage(userInfo)
    print("✅ Also sent via Firebase appDidReceiveMessage")
    
    // ✅ CRITICAL: Show banner/alert even when app is open
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
      print("✅ Showing notification with banner (iOS 14+)")
    } else {
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
    print("👆 ========================================")
    print("👆 User tapped notification")
    print("👆 ========================================")
    
    let userInfo = response.notification.request.content.userInfo
    let title = response.notification.request.content.title
    let body = response.notification.request.content.body
    
    print("📱 Action: \(response.actionIdentifier)")
    print("📱 Title: \(title)")
    print("📱 Body: \(body)")
    print("📱 userInfo: \(userInfo)")
    
    // ✅ Send to Flutter via MethodChannel
    sendNotificationToFlutter(
      title: title,
      body: body,
      userInfo: userInfo,
      isForeground: false
    )
    
    // ✅ Also try Firebase method (backup)
    Messaging.messaging().appDidReceiveMessage(userInfo)
    print("✅ Also sent via Firebase appDidReceiveMessage")
    
    completionHandler()
  }
  
  // MARK: - Send notification to Flutter via MethodChannel
  private func sendNotificationToFlutter(
    title: String,
    body: String,
    userInfo: [AnyHashable: Any],
    isForeground: Bool
  ) {
    guard let channel = notificationChannel else {
      print("❌ MethodChannel not initialized!")
      return
    }
    
    // Extract data from userInfo
    var dataDict: [String: Any] = [:]
    
    // Get 'type' from userInfo
    if let type = userInfo["type"] as? String {
      dataDict["type"] = type
    } else {
      dataDict["type"] = "general"
    }
    
    // Get 'image_url' from userInfo
    if let imageUrl = userInfo["image_url"] as? String {
      dataDict["image_url"] = imageUrl
    }
    
    // Get 'timestamp' from userInfo
    if let timestamp = userInfo["timestamp"] as? String {
      dataDict["timestamp"] = timestamp
    }
    
    // Get message ID
    var messageId = ""
    if let gcmMessageId = userInfo["gcm.message_id"] as? String {
      messageId = gcmMessageId
    } else {
      // Generate unique ID
      messageId = "\(Date().timeIntervalSince1970)"
    }
    
    // Prepare complete notification data
    let notificationData: [String: Any] = [
      "messageId": messageId,
      "title": title,
      "body": body,
      "data": dataDict,
      "isForeground": isForeground,
      "timestamp": ISO8601DateFormatter().string(from: Date())
    ]
    
    print("📤 Sending to Flutter via MethodChannel:")
    print("📤 MessageID: \(messageId)")
    print("📤 Title: \(title)")
    print("📤 Body: \(body)")
    print("📤 Type: \(dataDict["type"] ?? "unknown")")
    print("📤 Image URL: \(dataDict["image_url"] ?? "none")")
    print("📤 isForeground: \(isForeground)")
    
    // Send to Flutter
    channel.invokeMethod("onNotificationReceived", arguments: notificationData)
    print("✅ Notification sent to Flutter via MethodChannel")
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