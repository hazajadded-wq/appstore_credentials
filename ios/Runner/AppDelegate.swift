import UIKit
import Flutter
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  // ✅ CRITICAL: MethodChannel for direct communication with Flutter
  private var notificationChannel: FlutterMethodChannel?
  private var isChannelReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    print("🚀 ========================================")
    print("🚀 SalaryInfo App Started")
    print("🚀 ========================================")

    // ❌ لا تستدعي FirebaseApp.configure()
    // FlutterFire يقوم بها تلقائياً

    // ✅ CRITICAL: Set up MethodChannel FIRST
    let controller = window?.rootViewController as! FlutterViewController
    notificationChannel = FlutterMethodChannel(
      name: "com.pocket.salaryinfo/notifications",
      binaryMessenger: controller.binaryMessenger
    )
    
    if notificationChannel != nil {
      isChannelReady = true
      print("✅ MethodChannel created successfully")
      print("✅ Channel name: com.pocket.salaryinfo/notifications")
    } else {
      print("❌ FAILED to create MethodChannel!")
    }

    // ✅ CRITICAL: Set delegate BEFORE registering plugins
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      print("✅ UNUserNotificationCenter delegate set (BEFORE plugins)")
    }
    
    application.registerForRemoteNotifications()
    print("✅ Registered for remote notifications")

    GeneratedPluginRegistrant.register(with: self)
    print("✅ Plugins registered")

    // ✅ CRITICAL: Set delegate AGAIN AFTER plugins to ensure it's not overridden
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      print("✅ UNUserNotificationCenter delegate set (AFTER plugins)")
    }

    Messaging.messaging().delegate = self
    print("✅ Firebase Messaging delegate set")

    print("✅ ========================================")
    print("✅ AppDelegate initialization complete")
    print("✅ ========================================")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - APNs token
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("✅ APNs token set: \(token.prefix(20))...")
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
    print("📱 📱 📱 FOREGROUND NOTIFICATION RECEIVED 📱 📱 📱")
    print("📱 ========================================")
    
    let userInfo = notification.request.content.userInfo
    let title = notification.request.content.title
    let body = notification.request.content.body
    
    print("📱 Notification title: \(title)")
    print("📱 Notification body: \(body)")
    print("📱 Full userInfo: \(userInfo)")
    
    // ✅ Send to Flutter via MethodChannel (PRIMARY METHOD)
    let success = sendNotificationToFlutter(
      title: title,
      body: body,
      userInfo: userInfo,
      isForeground: true
    )
    
    if success {
      print("✅✅✅ Notification sent to Flutter via MethodChannel")
    } else {
      print("❌❌❌ FAILED to send notification to Flutter!")
    }
    
    // ✅ Also try Firebase method (backup)
    Messaging.messaging().appDidReceiveMessage(userInfo)
    print("✅ Also sent via Firebase appDidReceiveMessage (backup)")
    
    // ✅ CRITICAL: Show banner/alert even when app is open
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
      print("✅ Showing notification with banner (iOS 14+)")
    } else {
      completionHandler([.alert, .sound, .badge])
      print("✅ Showing notification with alert (iOS 13)")
    }
    
    print("📱 ========================================")
    print("📱 willPresent COMPLETE")
    print("📱 ========================================")
  }

  // MARK: - Notification tap
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    print("👆 ========================================")
    print("👆 👆 👆 USER TAPPED NOTIFICATION 👆 👆 👆")
    print("👆 ========================================")
    
    let userInfo = response.notification.request.content.userInfo
    let title = response.notification.request.content.title
    let body = response.notification.request.content.body
    
    print("📱 Action: \(response.actionIdentifier)")
    print("📱 Title: \(title)")
    print("📱 Body: \(body)")
    print("📱 Full userInfo: \(userInfo)")
    
    // ✅ Send to Flutter via MethodChannel
    let success = sendNotificationToFlutter(
      title: title,
      body: body,
      userInfo: userInfo,
      isForeground: false
    )
    
    if success {
      print("✅✅✅ Tapped notification sent to Flutter")
    } else {
      print("❌❌❌ FAILED to send tapped notification!")
    }
    
    // ✅ Also try Firebase method (backup)
    Messaging.messaging().appDidReceiveMessage(userInfo)
    print("✅ Also sent via Firebase appDidReceiveMessage (backup)")
    
    print("👆 ========================================")
    print("👆 didReceive COMPLETE")
    print("👆 ========================================")
    
    completionHandler()
  }
  
  // MARK: - Send notification to Flutter via MethodChannel
  @discardableResult
  private func sendNotificationToFlutter(
    title: String,
    body: String,
    userInfo: [AnyHashable: Any],
    isForeground: Bool
  ) -> Bool {
    
    print("📤 ========================================")
    print("📤 Preparing to send to Flutter...")
    print("📤 ========================================")
    
    guard isChannelReady else {
      print("❌ MethodChannel is NOT ready!")
      return false
    }
    
    guard let channel = notificationChannel else {
      print("❌ MethodChannel is nil!")
      return false
    }
    
    print("✅ MethodChannel is ready and available")
    
    // Extract data from userInfo
    var dataDict: [String: Any] = [:]
    
    // Get 'type' from userInfo
    if let type = userInfo["type"] as? String {
      dataDict["type"] = type
      print("📤 Found type: \(type)")
    } else if let gcmData = userInfo["gcm.notification.type"] as? String {
      dataDict["type"] = gcmData
      print("📤 Found type in gcm: \(gcmData)")
    } else {
      dataDict["type"] = "general"
      print("📤 No type found, using: general")
    }
    
    // Get 'image_url' from userInfo
    if let imageUrl = userInfo["image_url"] as? String {
      dataDict["image_url"] = imageUrl
      print("📤 Found image_url: \(imageUrl)")
    } else if let gcmImage = userInfo["gcm.notification.image_url"] as? String {
      dataDict["image_url"] = gcmImage
      print("📤 Found image_url in gcm: \(gcmImage)")
    } else {
      print("📤 No image_url found")
    }
    
    // Get 'timestamp' from userInfo
    if let timestamp = userInfo["timestamp"] as? String {
      dataDict["timestamp"] = timestamp
      print("📤 Found timestamp: \(timestamp)")
    } else {
      print("📤 No timestamp found")
    }
    
    // Get message ID
    var messageId = ""
    if let gcmMessageId = userInfo["gcm.message_id"] as? String {
      messageId = gcmMessageId
      print("📤 Found gcm.message_id: \(messageId)")
    } else if let msgId = userInfo["message_id"] as? String {
      messageId = msgId
      print("📤 Found message_id: \(messageId)")
    } else {
      // Generate unique ID
      messageId = "ios_\(Date().timeIntervalSince1970)"
      print("📤 Generated messageId: \(messageId)")
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
    
    print("📤 ========================================")
    print("📤 Sending notification data to Flutter:")
    print("📤 MessageID: \(messageId)")
    print("📤 Title: \(title)")
    print("📤 Body: \(body)")
    print("📤 Type: \(dataDict["type"] ?? "unknown")")
    print("📤 Image URL: \(dataDict["image_url"] ?? "none")")
    print("📤 isForeground: \(isForeground)")
    print("📤 Full data: \(notificationData)")
    print("📤 ========================================")
    
    // Send to Flutter
    channel.invokeMethod("onNotificationReceived", arguments: notificationData)
    print("✅✅✅ channel.invokeMethod called successfully!")
    print("✅ Method: onNotificationReceived")
    print("✅ Arguments sent")
    
    return true
  }
}

// MARK: - Firebase Messaging
extension AppDelegate: MessagingDelegate {

  func messaging(
    _ messaging: Messaging,
    didReceiveRegistrationToken fcmToken: String?
  ) {
    guard let token = fcmToken else { 
      print("❌ No FCM token received")
      return 
    }
    print("✅ FCM token received")
    print("✅ Token (first 30 chars): \(String(token.prefix(30)))...")
  }
}