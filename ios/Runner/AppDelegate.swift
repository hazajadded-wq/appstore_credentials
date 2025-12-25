import UIKit
import Flutter
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var notificationChannel: FlutterMethodChannel?
  private var isChannelReady = false
  
  // ✅ Key for storing notifications
  private let pendingNotificationsKey = "pending_notifications"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    print("🚀 SalaryInfo App Started")

    let controller = window?.rootViewController as! FlutterViewController
    notificationChannel = FlutterMethodChannel(
      name: "com.pocket.salaryinfo/notifications",
      binaryMessenger: controller.binaryMessenger
    )
    
    if notificationChannel != nil {
      isChannelReady = true
      print("✅ MethodChannel created successfully")
    } else {
      print("❌ FAILED to create MethodChannel!")
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      print("✅ UNUserNotificationCenter delegate set (BEFORE plugins)")
    }
    
    application.registerForRemoteNotifications()
    print("✅ Registered for remote notifications")

    GeneratedPluginRegistrant.register(with: self)
    print("✅ Plugins registered")

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      print("✅ UNUserNotificationCenter delegate set (AFTER plugins)")
    }

    Messaging.messaging().delegate = self
    print("✅ Firebase Messaging delegate set")
    
    // ✅ IMPORTANT: Check for pending notifications from UserDefaults
    checkAndSendPendingNotifications()
    
    print("✅ AppDelegate initialization complete")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // ✅ NEW: Check for pending notifications saved in UserDefaults
  private func checkAndSendPendingNotifications() {
    guard let savedData = UserDefaults.standard.array(forKey: pendingNotificationsKey) as? [[String: Any]] else {
      print("📭 No pending notifications found")
      return
    }
    
    print("📬 ========================================")
    print("📬 Found \(savedData.count) pending notifications!")
    print("📬 ========================================")
    
    // Send each pending notification to Flutter
    for notificationData in savedData {
      print("📬 Sending pending notification: \(notificationData["title"] ?? "Unknown")")
      
      if isChannelReady, let channel = notificationChannel {
        channel.invokeMethod("onNotificationReceived", arguments: notificationData)
      }
    }
    
    // Clear pending notifications
    UserDefaults.standard.removeObject(forKey: pendingNotificationsKey)
    UserDefaults.standard.synchronize()
    print("✅ Cleared pending notifications from UserDefaults")
  }
  
  // ✅ NEW: Save notification to UserDefaults (for background delivery)
  private func savePendingNotification(_ notificationData: [String: Any]) {
    var pendingNotifications = UserDefaults.standard.array(forKey: pendingNotificationsKey) as? [[String: Any]] ?? []
    pendingNotifications.append(notificationData)
    UserDefaults.standard.set(pendingNotifications, forKey: pendingNotificationsKey)
    UserDefaults.standard.synchronize()
    print("💾 Saved notification to UserDefaults (count: \(pendingNotifications.count))")
  }

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

  // MARK: - Foreground notification
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    print("📱 ========================================")
    print("📱 FOREGROUND NOTIFICATION RECEIVED")
    print("📱 ========================================")
    
    let userInfo = notification.request.content.userInfo
    let title = notification.request.content.title
    let body = notification.request.content.body
    
    print("📱 Title: \(title)")
    print("📱 Body: \(body)")
    
    // Extract and prepare notification data
    let notificationData = extractNotificationData(
      title: title,
      body: body,
      userInfo: userInfo,
      isForeground: true,
      shouldNavigate: false
    )
    
    // ✅ IMPORTANT: Save to UserDefaults as backup
    savePendingNotification(notificationData)
    
    // Send to Flutter
    let success = sendNotificationToFlutter(notificationData)
    
    if success {
      print("✅ Notification sent to Flutter")
    } else {
      print("⚠️ Failed to send to Flutter, but saved to UserDefaults")
    }
    
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
    
    print("📱 willPresent COMPLETE")
  }

  // MARK: - Notification tap (USER CLICKED!)
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
    
    print("👆 Title: \(title)")
    print("👆 Body: \(body)")
    print("👆 🚀 WILL NAVIGATE TO NOTIFICATIONS PAGE!")
    
    // Extract and prepare notification data
    let notificationData = extractNotificationData(
      title: title,
      body: body,
      userInfo: userInfo,
      isForeground: false,
      shouldNavigate: true  // ✅ Navigate when tapped!
    )
    
    // ✅ IMPORTANT: Save to UserDefaults (in case Flutter not ready yet)
    savePendingNotification(notificationData)
    
    // Send to Flutter
    let success = sendNotificationToFlutter(notificationData)
    
    if success {
      print("✅ Tapped notification sent to Flutter with NAVIGATE flag")
    } else {
      print("⚠️ Failed to send to Flutter, but saved to UserDefaults")
    }
    
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    print("👆 didReceive COMPLETE")
    
    completionHandler()
  }
  
  // MARK: - Extract notification data
  private func extractNotificationData(
    title: String,
    body: String,
    userInfo: [AnyHashable: Any],
    isForeground: Bool,
    shouldNavigate: Bool
  ) -> [String: Any] {
    
    var dataDict: [String: Any] = [:]
    
    if let type = userInfo["type"] as? String {
      dataDict["type"] = type
    } else if let gcmData = userInfo["gcm.notification.type"] as? String {
      dataDict["type"] = gcmData
    } else {
      dataDict["type"] = "general"
    }
    
    if let imageUrl = userInfo["image_url"] as? String {
      dataDict["image_url"] = imageUrl
    } else if let gcmImage = userInfo["gcm.notification.image_url"] as? String {
      dataDict["image_url"] = gcmImage
    }
    
    if let timestamp = userInfo["timestamp"] as? String {
      dataDict["timestamp"] = timestamp
    }
    
    var messageId = ""
    if let gcmMessageId = userInfo["gcm.message_id"] as? String {
      messageId = gcmMessageId
    } else if let msgId = userInfo["message_id"] as? String {
      messageId = msgId
    } else {
      messageId = "ios_\(Date().timeIntervalSince1970)"
    }
    
    return [
      "messageId": messageId,
      "title": title,
      "body": body,
      "data": dataDict,
      "isForeground": isForeground,
      "shouldNavigate": shouldNavigate,
      "timestamp": ISO8601DateFormatter().string(from: Date())
    ]
  }
  
  // MARK: - Send notification to Flutter
  @discardableResult
  private func sendNotificationToFlutter(_ notificationData: [String: Any]) -> Bool {
    
    guard isChannelReady else {
      print("❌ MethodChannel is NOT ready!")
      return false
    }
    
    guard let channel = notificationChannel else {
      print("❌ MethodChannel is nil!")
      return false
    }
    
    print("✅ MethodChannel is ready")
    print("📤 Sending: \(notificationData["title"] ?? "Unknown")")
    print("📤 shouldNavigate: \(notificationData["shouldNavigate"] ?? false)")
    
    channel.invokeMethod("onNotificationReceived", arguments: notificationData)
    print("✅ channel.invokeMethod called successfully!")
    
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
