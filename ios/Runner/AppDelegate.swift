import UIKit
import Flutter
import UserNotifications
import FirebaseCore
import FirebaseMessaging

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    private let CHANNEL = "com.pocket.salaryinfo/notifications"
    private let WEBVIEW_CHANNEL = "snap_webview"
    private var methodChannel: FlutterMethodChannel?
    private var webviewChannel: FlutterMethodChannel?
    
    private var processedNotificationIds = Set<String>()
    private let maxProcessedIds = 100
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        setupNotifications(application: application)
        setupMethodChannel()
        
        print("✅ AppDelegate initialized - Firebase configured by Flutter")
        
        // ✅ FIX: Check if app was launched from notification
        if let notification = launchOptions?[.remoteNotification] as? [String: AnyObject] {
            print("🚀 App launched from notification")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let notificationData = self.extractNotificationData(
                    from: notification,
                    identifier: "launch_\(Date().timeIntervalSince1970)"
                )
                self.sendNotificationToFlutter(notificationData)
            }
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func setupNotifications(application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in
                if let error = error {
                    print("❌ Error requesting authorization: \(error)")
                } else {
                    print("✅ Notification authorization granted: \(granted)")
                }
            }
        )
        
        application.registerForRemoteNotifications()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Messaging.messaging().delegate = self
            print("✅ Firebase Messaging delegate set")
        }
        
        print("✅ Notifications setup completed")
    }
    
    private func setupMethodChannel() {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            print("❌ Failed to get FlutterViewController")
            return
        }
        
        methodChannel = FlutterMethodChannel(
            name: CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )
        
        webviewChannel = FlutterMethodChannel(
            name: WEBVIEW_CHANNEL,
            binaryMessenger: controller.binaryMessenger
        )
        
        webviewChannel?.setMethodCallHandler { [weak self] (call, result) in
            if call.method == "takeSnapshot" {
                self?.takeScreenshot(result: result)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
        
        print("✅ MethodChannel setup completed (notifications + webview)")
    }
    
    private func takeScreenshot(result: @escaping FlutterResult) {
        guard let window = self.window else {
            print("❌ Window not available for screenshot")
            result(FlutterError(code: "NO_WINDOW", message: "Window not available", details: nil))
            return
        }
        
        print("📸 Taking screenshot...")
        
        let bounds = window.bounds
        UIGraphicsBeginImageContextWithOptions(bounds.size, false, UIScreen.main.scale)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            print("❌ Failed to create graphics context")
            UIGraphicsEndImageContext()
            result(FlutterError(code: "CONTEXT_ERROR", message: "Failed to create graphics context", details: nil))
            return
        }
        
        window.layer.render(in: context)
        
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            print("❌ Failed to get image from context")
            UIGraphicsEndImageContext()
            result(FlutterError(code: "IMAGE_ERROR", message: "Failed to capture image", details: nil))
            return
        }
        
        UIGraphicsEndImageContext()
        
        guard let imageData = image.pngData() else {
            print("❌ Failed to convert image to PNG")
            result(FlutterError(code: "PNG_ERROR", message: "Failed to convert to PNG", details: nil))
            return
        }
        
        print("✅ Screenshot captured successfully: \(imageData.count) bytes")
        
        let flutterData = FlutterStandardTypedData(bytes: imageData)
        result(flutterData.data)
    }
    
    private func isNotificationProcessed(_ notificationId: String) -> Bool {
        if processedNotificationIds.contains(notificationId) {
            print("⚠️ Duplicate notification detected: \(notificationId)")
            return true
        }
        
        processedNotificationIds.insert(notificationId)
        
        if processedNotificationIds.count > maxProcessedIds {
            let elementsToRemove = processedNotificationIds.count - maxProcessedIds
            for _ in 0..<elementsToRemove {
                if let first = processedNotificationIds.first {
                    processedNotificationIds.remove(first)
                }
            }
            print("🧹 Cleaned up \(elementsToRemove) old notification IDs")
        }
        
        return false
    }
    
    private func sendNotificationToFlutter(_ notification: [String: Any]) -> Bool {
        guard let channel = methodChannel else {
            print("❌ MethodChannel not initialized")
            return false
        }
        
        if let notificationId = notification["id"] as? String {
            if isNotificationProcessed(notificationId) {
                print("🚫 Skipping duplicate notification: \(notificationId)")
                return false
            }
        }
        
        print("📤 Sending notification to Flutter:")
        print("   Title: \(notification["title"] ?? "N/A")")
        print("   Body: \(notification["body"] ?? "N/A")")
        print("   Type: \(notification["type"] ?? "N/A")")
        
        channel.invokeMethod("onNotificationReceived", arguments: notification)
        
        return true
    }
    
    private func extractNotificationData(from userInfo: [AnyHashable: Any], identifier: String) -> [String: Any] {
        var notificationData: [String: Any] = [
            "id": identifier,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        if let aps = userInfo["aps"] as? [String: Any],
           let alert = aps["alert"] as? [String: Any] {
            notificationData["title"] = alert["title"] as? String ?? "إشعار جديد"
            notificationData["body"] = alert["body"] as? String ?? ""
        } else if let aps = userInfo["aps"] as? [String: Any],
                  let alertString = aps["alert"] as? String {
            notificationData["title"] = "إشعار جديد"
            notificationData["body"] = alertString
        }
        
        notificationData["type"] = userInfo["type"] as? String ?? "general"
        
        if let imageUrl = userInfo["image_url"] as? String {
            notificationData["imageUrl"] = imageUrl
        }
        
        var additionalData: [String: Any] = [:]
        for (key, value) in userInfo {
            if let keyString = key as? String,
               keyString != "aps" &&
               keyString != "gcm.message_id" &&
               keyString != "google.c.a.e" {
                additionalData[keyString] = value
            }
        }
        
        if !additionalData.isEmpty {
            notificationData["data"] = additionalData
        }
        
        return notificationData
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate {
    
    // ✅ FIX: Handle foreground notifications properly
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        print("🔔 willPresent - App in FOREGROUND")
        print("📱 Notification ID: \(notification.request.identifier)")
        
        let notificationData = extractNotificationData(from: userInfo, identifier: notification.request.identifier)
        
        // ✅ Always send to Flutter
        let _ = sendNotificationToFlutter(notificationData)
        
        // ✅ Show notification banner even when app is in foreground
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge, .list])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    // ✅ FIX: Handle tapped notifications properly
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        print("👆 didReceive - User TAPPED notification")
        print("📱 Notification ID: \(response.notification.request.identifier)")
        
        let notificationData = extractNotificationData(from: userInfo, identifier: response.notification.request.identifier)
        
        // ✅ Send to Flutter
        let _ = sendNotificationToFlutter(notificationData)
        
        // ✅ Remove from notification center
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [response.notification.request.identifier]
        )
        print("🗑️ Removed tapped notification from Notification Center")
        
        completionHandler()
    }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else {
            print("❌ FCM token is nil")
            return
        }
        
        print("🔑 FCM Token: \(token)")
        
        let dataDict: [String: String] = ["token": token]
        NotificationCenter.default.post(
            name: Notification.Name("FCMToken"),
            object: nil,
            userInfo: dataDict
        )
    }
}