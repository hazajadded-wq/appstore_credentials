import UIKit
import Flutter
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var notificationChannel: FlutterMethodChannel?
  private var isChannelReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    print("🚀 ========================================")
    print("🚀 SalaryInfo App Started")
    print("🚀 ========================================")

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
      print("✅ UNUserNotificationCenter delegate set")
    }
    
    application.registerForRemoteNotifications()
    print("✅ Registered for remote notifications")

    GeneratedPluginRegistrant.register(with: self)
    print("✅ Plugins registered")

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    Messaging.messaging().delegate = self
    print("✅ Firebase Messaging delegate set")
    
    // ✅ CRITICAL: Check for delivered notifications
    checkDeliveredNotifications()
    
    print("✅ AppDelegate initialization complete")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // ✅ SOLUTION: Read delivered notifications from iOS Notification Center
  private func checkDeliveredNotifications() {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
        print("📬 ========================================")
        print("📬 Checking delivered notifications...")
        print("📬 Found: \(notifications.count) notifications")
        print("📬 ========================================")
        
        guard !notifications.isEmpty else {
          print("📭 No delivered notifications found")
          return
        }
        
        // Process each delivered notification
        for notification in notifications {
          let content = notification.request.content
          let userInfo = content.userInfo
          
          print("📬 Processing: \(content.title)")
          
          // Extract notification data
          let notificationData = self.extractNotificationData(
            title: content.title,
            body: content.body,
            userInfo: userInfo,
            isForeground: false,
            shouldNavigate: false  // Don't navigate, just save
          )
          
          // Send to Flutter
          DispatchQueue.main.async {
            self.sendNotificationToFlutter(notificationData)
          }
        }
        
        // ✅ IMPORTANT: Clear delivered notifications after processing
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        print("✅ Cleared all delivered notifications from Notification Center")
      }
    }
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

  // MARK: - Foreground notification (App is open)
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
    
    // Extract notification data
    let notificationData = extractNotificationData(
      title: title,
      body: body,
      userInfo: userInfo,
      isForeground: true,
      shouldNavigate: false
    )
    
    // Send to Flutter
    let success = sendNotificationToFlutter(notificationData)
    
    if success {
      print("✅ Notification sent to Flutter")
    } else {
      print("❌ Failed to send to Flutter")
    }
    
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    // Show banner
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
    
    print("📱 willPresent COMPLETE")
  }

  // MARK: - Notification tap (User clicked notification)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    print("👆 ========================================")
    print("👆 USER TAPPED NOTIFICATION")
    print("👆 ========================================")
    
    let userInfo = response.notification.request.content.userInfo
    let title = response.notification.request.content.title
    let body = response.notification.request.content.body
    
    print("👆 Title: \(title)")
    print("👆 Body: \(body)")
    print("👆 🚀 WILL NAVIGATE TO NOTIFICATIONS PAGE!")
    
    // Extract notification data
    let notificationData = extractNotificationData(
      title: title,
      body: body,
      userInfo: userInfo,
      isForeground: false,
      shouldNavigate: true  // ✅ Navigate when tapped!
    )
    
    // Send to Flutter
    let success = sendNotificationToFlutter(notificationData)
    
    if success {
      print("✅ Tapped notification sent to Flutter with NAVIGATE flag")
    } else {
      print("❌ Failed to send tapped notification")
    }
    
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    // Remove this specific notification from Notification Center
    let identifier = response.notification.request.identifier
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    print("✅ Removed notification from Notification Center: \(identifier)")
    
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
    
    // Extract type
    if let type = userInfo["type"] as? String {
      dataDict["type"] = type
    } else if let gcmData = userInfo["gcm.notification.type"] as? String {
      dataDict["type"] = gcmData
    } else {
      dataDict["type"] = "general"
    }
    
    // Extract image URL
    if let imageUrl = userInfo["image_url"] as? String {
      dataDict["image_url"] = imageUrl
    } else if let gcmImage = userInfo["gcm.notification.image_url"] as? String {
      dataDict["image_url"] = gcmImage
    }
    
    // Extract timestamp
    if let timestamp = userInfo["timestamp"] as? String {
      dataDict["timestamp"] = timestamp
    }
    
    // Extract message ID
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
    
    print("📤 Sending to Flutter:")
    print("📤 Title: \(notificationData["title"] ?? "Unknown")")
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
