import UIKit
import Flutter
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 1. Setup Method Channel for WebView Snapshots
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let webviewChannel = FlutterMethodChannel(name: "snap_webview",
                                              binaryMessenger: controller.binaryMessenger)
    
    webviewChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if (call.method == "takeSnapshot") {
        self.takeScreenshot(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    // 2. Register Plugins
    GeneratedPluginRegistrant.register(with: self)
    
    // 3. CRITICAL: Setup Notification Center Delegate
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { _, _ in }
      )
    }
    
    application.registerForRemoteNotifications()
    
    // 4. Set Firebase Messaging Delegate
    Messaging.messaging().delegate = self
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Helper function for WebView screenshots
  private func takeScreenshot(result: @escaping FlutterResult) {
      guard let window = self.window else {
          result(FlutterError(code: "NO_WINDOW", message: "Window not available", details: nil))
          return
      }
      
      let bounds = window.bounds
      UIGraphicsBeginImageContextWithOptions(bounds.size, false, 6.0)
      
      guard let context = UIGraphicsGetCurrentContext() else {
          UIGraphicsEndImageContext()
          result(FlutterError(code: "CONTEXT_ERROR", message: "Failed to create graphics context", details: nil))
          return
      }
      
      window.layer.render(in: context)
      
      guard let image = UIGraphicsGetImageFromCurrentImageContext(), let imageData = image.pngData() else {
          UIGraphicsEndImageContext()
          result(FlutterError(code: "IMAGE_ERROR", message: "Failed to capture image", details: nil))
          return
      }
      
      UIGraphicsEndImageContext()
      let flutterData = FlutterStandardTypedData(bytes: imageData)
      result(flutterData.data)
  }
  
  // MARK: - UNUserNotificationCenterDelegate Methods
  // Note: We don't declare conformance again as FlutterAppDelegate already conforms to it
  
  // CRITICAL: Called when notification arrives while app is in FOREGROUND
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    
    print("📱 [iOS] Foreground notification received")
    print("📱 [iOS] UserInfo: \(userInfo)")
    
    // Save to local storage via Flutter
    saveNotificationToFlutter(userInfo: userInfo)
    
    // Show banner, badge, and sound
    if #available(iOS 14.0, *) {
      completionHandler([[.banner, .badge, .sound]])
    } else {
      completionHandler([[.alert, .badge, .sound]])
    }
  }
  
  // Called when user TAPS on notification
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    
    print("👆 [iOS] Notification tapped")
    print("👆 [iOS] UserInfo: \(userInfo)")
    
    // Save to local storage
    saveNotificationToFlutter(userInfo: userInfo)
    
    // CRITICAL: Navigate to notifications screen
    if let controller = window?.rootViewController as? FlutterViewController {
      let navigationChannel = FlutterMethodChannel(
        name: "notification_handler",
        binaryMessenger: controller.binaryMessenger
      )
      navigationChannel.invokeMethod("navigateToNotifications", arguments: nil)
      print("📱 [iOS] Sent navigation command to Flutter")
    }
    
    completionHandler()
  }
  
  // CRITICAL: Save notification to Flutter's storage system
  private func saveNotificationToFlutter(userInfo: [AnyHashable: Any]) {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      print("❌ [iOS] FlutterViewController not found")
      return
    }
    
    let channel = FlutterMethodChannel(
      name: "notification_handler",
      binaryMessenger: controller.binaryMessenger
    )
    
    // Convert userInfo to Swift Dictionary
    var notificationData: [String: Any] = [:]
    
    // CRITICAL: Extract title and body from multiple possible locations, prioritizing data
    var title = ""
    var body = ""
    var imageUrl: String? = nil
    var type = "general"
    
    // First, try to get from data payload (highest priority)
    if let data = userInfo["data"] as? [String: Any] {
      title = data["title"] as? String ?? title
      body = data["body"] as? String ?? body
      type = data["type"] as? String ?? type
      imageUrl = data["image_url"] as? String ?? data["imageUrl"] as? String ?? imageUrl
    }
    
    // Then try FCM notification structure
    if let fcmTitle = userInfo["gcm.notification.title"] as? String, !fcmTitle.isEmpty {
      title = fcmTitle
    }
    if let fcmBody = userInfo["gcm.notification.body"] as? String, !fcmBody.isEmpty {
      body = fcmBody
    }
    
    // Try direct keys
    if let directTitle = userInfo["title"] as? String, !directTitle.isEmpty {
      title = directTitle
    }
    if let directBody = userInfo["body"] as? String, !directBody.isEmpty {
      body = directBody
    }
    
    // Try notification object first
    if let aps = userInfo["aps"] as? [String: Any],
       let alert = aps["alert"] as? [String: Any] {
      if let apsTitle = alert["title"] as? String, !apsTitle.isEmpty {
        title = apsTitle
      }
      if let apsBody = alert["body"] as? String, !apsBody.isEmpty {
        body = apsBody
      }
    }
    
    // Fallback to default if still empty
    if title.isEmpty {
      title = "إشعار جديد"
    }
    
    // Image URL from various sources
    if imageUrl == nil {
      imageUrl = userInfo["image_url"] as? String
        ?? userInfo["imageUrl"] as? String
        ?? userInfo["gcm.notification.image_url"] as? String
    }
    
    // Type from various sources
    if let userType = userInfo["type"] as? String {
      type = userType
    }
    
    let messageId = userInfo["gcm.message_id"] as? String 
                    ?? userInfo["message_id"] as? String
                    ?? UUID().uuidString
    
    notificationData["id"] = messageId
    notificationData["title"] = title
    notificationData["body"] = body
    notificationData["imageUrl"] = imageUrl
    notificationData["type"] = type
    notificationData["timestamp"] = Int(Date().timeIntervalSince1970 * 1000)
    notificationData["data"] = userInfo as? [String: Any] ?? [:]
    notificationData["isRead"] = false
    
    print("💾 [iOS] Saving notification")
    print("📱 [iOS] Title: \(title)")
    print("📱 [iOS] Body: \(body)")
    print("📱 [iOS] Type: \(type)")
    
    // Send to Flutter
    channel.invokeMethod("saveNotification", arguments: notificationData)
  }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
  
  // Called when FCM token is refreshed
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("🔑 [iOS] FCM Token: \(fcmToken ?? "nil")")
    
    // You can send this token to your server
    if let token = fcmToken {
      let dataDict: [String: String] = ["token": token]
      NotificationCenter.default.post(
        name: Notification.Name("FCMToken"),
        object: nil,
        userInfo: dataDict
      )
    }
  }
}