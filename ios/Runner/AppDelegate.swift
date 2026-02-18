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
    
    // 5. CRITICAL FIX: Listen for app termination to clean up WebView before Flutter engine shuts down
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppWillTerminate),
      name: UIApplication.willTerminateNotification,
      object: nil
    )
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // CRITICAL FIX: Clean up WebView platform views before Flutter engine teardown
  @objc private func handleAppWillTerminate() {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "webview_cleanup",
        binaryMessenger: controller.binaryMessenger
      )
      channel.invokeMethod("dispose", arguments: nil)
      removeWKWebViews(from: controller.view)
    }
  }
  
  private func removeWKWebViews(from view: UIView) {
    for subview in view.subviews {
      if NSStringFromClass(type(of: subview)).contains("WKWebView") {
        subview.removeFromSuperview()
      } else {
        removeWKWebViews(from: subview)
      }
    }
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
  
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    
    print("📱 [iOS] Foreground notification received")
    print("📱 [iOS] UserInfo: \(userInfo)")
    
    saveNotificationToFlutter(userInfo: userInfo)
    
    if #available(iOS 14.0, *) {
      completionHandler([[.banner, .badge, .sound]])
    } else {
      completionHandler([[.alert, .badge, .sound]])
    }
  }
  
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    
    print("👆 [iOS] Notification tapped")
    print("👆 [iOS] UserInfo: \(userInfo)")
    
    saveNotificationToFlutter(userInfo: userInfo)
    
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
  
  private func saveNotificationToFlutter(userInfo: [AnyHashable: Any]) {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      print("❌ [iOS] FlutterViewController not found")
      return
    }
    
    let channel = FlutterMethodChannel(
      name: "notification_handler",
      binaryMessenger: controller.binaryMessenger
    )
    
    var notificationData: [String: Any] = [:]
    
    var title = ""
    var body = ""
    var imageUrl: String? = nil
    var type = "general"
    
    if let data = userInfo["data"] as? [String: Any] {
      title = data["title"] as? String ?? title
      body = data["body"] as? String ?? body
      type = data["type"] as? String ?? type
      imageUrl = data["image_url"] as? String ?? data["imageUrl"] as? String ?? imageUrl
    }
    
    if let fcmTitle = userInfo["gcm.notification.title"] as? String, !fcmTitle.isEmpty {
      title = fcmTitle
    }
    if let fcmBody = userInfo["gcm.notification.body"] as? String, !fcmBody.isEmpty {
      body = fcmBody
    }
    
    if let directTitle = userInfo["title"] as? String, !directTitle.isEmpty {
      title = directTitle
    }
    if let directBody = userInfo["body"] as? String, !directBody.isEmpty {
      body = directBody
    }
    
    if let aps = userInfo["aps"] as? [String: Any],
       let alert = aps["alert"] as? [String: Any] {
      if let apsTitle = alert["title"] as? String, !apsTitle.isEmpty {
        title = apsTitle
      }
      if let apsBody = alert["body"] as? String, !apsBody.isEmpty {
        body = apsBody
      }
    }
    
    if title.isEmpty {
      title = "إشعار جديد"
    }
    
    if imageUrl == nil {
      imageUrl = userInfo["image_url"] as? String
        ?? userInfo["imageUrl"] as? String
        ?? userInfo["gcm.notification.image_url"] as? String
    }
    
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
    
    channel.invokeMethod("saveNotification", arguments: notificationData)
  }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
  
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("🔑 [iOS] FCM Token: \(fcmToken ?? "nil")")
    
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
