import UIKit
import Flutter
import UserNotifications
import FirebaseCore
import FirebaseMessaging

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    private let CHANNEL = "com.pocket.salaryinfo/notifications"
    private var methodChannel: FlutterMethodChannel?
    
    // ✅ Track processed notification IDs to prevent duplicates
    private var processedNotificationIds = Set<String>()
    private let maxProcessedIds = 100 // Keep last 100 IDs
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // ⚠️ CRITICAL: Do NOT call FirebaseApp.configure() here!
        // It's already called in main.dart Flutter code
        // Calling it twice will cause: "The default Firebase app has already been configured"
        
        // Setup notifications
        setupNotifications(application: application)
        
        // Setup MethodChannel
        setupMethodChannel()
        
        print("✅ AppDelegate initialized - Firebase configured by Flutter")
        
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
        
        // Set Firebase Messaging delegate AFTER Flutter initializes Firebase
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
        
        print("✅ MethodChannel setup completed")
    }
    
    // ✅ FIXED: Add duplicate detection
    private func isNotificationProcessed(_ notificationId: String) -> Bool {
        if processedNotificationIds.contains(notificationId) {
            print("⚠️ Duplicate notification detected: \(notificationId)")
            return true
        }
        
        // Add to processed set
        processedNotificationIds.insert(notificationId)
        
        // Keep set size manageable
        if processedNotificationIds.count > maxProcessedIds {
            // Remove excess elements (Sets don't have removeFirst for multiple elements)
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
        
        // ✅ Check for duplicates
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
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate {
    
    // عندما يكون التطبيق في الـ foreground
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        print("🔔 willPresent - App in FOREGROUND")
        print("📱 Notification ID: \(notification.request.identifier)")
        
        // استخراج البيانات
        let notificationData = extractNotificationData(from: userInfo, identifier: notification.request.identifier)
        
        // إرسال إلى Flutter
        let success = sendNotificationToFlutter(notificationData)
        
        if success {
            print("✅ Notification sent to Flutter successfully")
        } else {
            print("❌ Failed to send notification to Flutter (possibly duplicate)")
        }
        
        // عرض الإشعار
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    // عندما ينقر المستخدم على الإشعار
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        print("👆 didReceive - User TAPPED notification")
        print("📱 Notification ID: \(response.notification.request.identifier)")
        
        // ✅ IMPORTANT: Don't send to Flutter here - let Flutter's onMessageOpenedApp handle it
        // This prevents duplicate handling when user taps notification
        print("ℹ️ Notification tap will be handled by Flutter's onMessageOpenedApp")
        
        // حذف هذا الإشعار فقط من Notification Center
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [response.notification.request.identifier]
        )
        print("🗑️ Removed tapped notification from Notification Center")
        
        completionHandler()
    }
    
    private func extractNotificationData(from userInfo: [AnyHashable: Any], identifier: String) -> [String: Any] {
        var notificationData: [String: Any] = [
            "id": identifier, // ✅ Changed from "messageId" to "id" to match Flutter
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        
        // استخراج title و body
        if let aps = userInfo["aps"] as? [String: Any],
           let alert = aps["alert"] as? [String: Any] {
            notificationData["title"] = alert["title"] as? String ?? "إشعار جديد"
            notificationData["body"] = alert["body"] as? String ?? ""
        } else if let aps = userInfo["aps"] as? [String: Any],
                  let alertString = aps["alert"] as? String {
            notificationData["title"] = "إشعار جديد"
            notificationData["body"] = alertString
        }
        
        // استخراج البيانات المخصصة
        notificationData["type"] = userInfo["type"] as? String ?? "general"
        
        if let imageUrl = userInfo["image_url"] as? String {
            notificationData["imageUrl"] = imageUrl
        }
        
        // إضافة جميع البيانات الإضافية
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
