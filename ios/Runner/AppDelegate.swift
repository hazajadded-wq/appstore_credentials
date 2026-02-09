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
    
    // منع تكرار معالجة نفس الإشعار
    private var processedNotificationIds = Set<String>()
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // ✅ GeneratedPluginRegistrant handles Firebase initialization automatically
        GeneratedPluginRegistrant.register(with: self)
        
        setupNotifications(application: application)
        setupMethodChannel()
        
        print("✅ AppDelegate initialized")
        
        // التحقق مما إذا كان التطبيق قد تم تشغيله عن طريق النقر على إشعار
        if let notification = launchOptions?[.remoteNotification] as? [String: AnyObject] {
            print("🚀 App launched from notification (Cold Start)")
            // تأخير بسيط لضمان جاهزية Flutter
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
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
        if #available(iOS 10.0, *) {
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
        }
        
        application.registerForRemoteNotifications()
        Messaging.messaging().delegate = self
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
        
        print("✅ MethodChannel setup completed")
    }
    
    private func takeScreenshot(result: @escaping FlutterResult) {
        guard let window = self.window else {
            result(FlutterError(code: "NO_WINDOW", message: "Window not available", details: nil))
            return
        }
        
        let bounds = window.bounds
        UIGraphicsBeginImageContextWithOptions(bounds.size, false, UIScreen.main.scale)
        
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
    
    private func sendNotificationToFlutter(_ notification: [String: Any]) -> Bool {
        guard let channel = methodChannel else {
            print("❌ MethodChannel not initialized")
            return false
        }
        
        // التحقق من التكرار
        if let id = notification["id"] as? String {
            if processedNotificationIds.contains(id) {
                print("🚫 Duplicate notification skipped: \(id)")
                return false
            }
            processedNotificationIds.insert(id)
            // تنظيف القائمة إذا كبرت
            if processedNotificationIds.count > 100 {
                processedNotificationIds.removeAll()
            }
        }
        
        print("📤 Sending notification to Flutter via MethodChannel...")
        channel.invokeMethod("onNotificationReceived", arguments: notification)
        return true
    }
    
    private func extractNotificationData(from userInfo: [AnyHashable: Any], identifier: String) -> [String: Any] {
        var notificationData: [String: Any] = [
            "id": identifier,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        // استخراج العنوان والجسم من aps
        if let aps = userInfo["aps"] as? [String: Any],
           let alert = aps["alert"] as? [String: Any] {
            notificationData["title"] = alert["title"] as? String ?? "إشعار جديد"
            notificationData["body"] = alert["body"] as? String ?? ""
        } else if let aps = userInfo["aps"] as? [String: Any],
                  let alertString = aps["alert"] as? String {
            notificationData["title"] = "إشعار جديد"
            notificationData["body"] = alertString
        } else {
            // محاولة الاستخراج من المستوى الأعلى (بيانات مباشرة من FCM)
            notificationData["title"] = userInfo["title"] as? String ?? "إشعار جديد"
            notificationData["body"] = userInfo["body"] as? String ?? ""
        }
        
        notificationData["type"] = userInfo["type"] as? String ?? "general"
        
        if let imageUrl = userInfo["image_url"] as? String ?? userInfo["image"] as? String {
            notificationData["imageUrl"] = imageUrl
        }
        
        // تجميع البيانات الإضافية
        var additionalData: [String: Any] = [:]
        for (key, value) in userInfo {
            if let keyString = key as? String,
               keyString != "aps" && keyString != "gcm.message_id" {
                additionalData[keyString] = value
            }
        }
        notificationData["data"] = additionalData
        
        return notificationData
    }
    
    // ✅ معالجة الإشعارات عندما يكون التطبيق في الواجهة (Foreground)
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        print("🔔 willPresent - App in FOREGROUND")
        
        let notificationData = extractNotificationData(
            from: userInfo,
            identifier: notification.request.identifier
        )
        
        // إرسال البيانات لـ Flutter لحفظها في قاعدة البيانات
        _ = sendNotificationToFlutter(notificationData)
        
        // عرض الإشعار كـ Banner وصوت وشارة حتى لو التطبيق مفتوح
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge, .list])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    // ✅ معالجة النقر على الإشعار (Background / Terminated -> Open)
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("👆 didReceive - User TAPPED notification")
        
        let notificationData = extractNotificationData(
            from: userInfo,
            identifier: response.notification.request.identifier
        )
        
        _ = sendNotificationToFlutter(notificationData)
        
        completionHandler()
    }
    
    // ✅ دعم Silent Push Notifications / Background Fetch
    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("🔄 didReceiveRemoteNotification (Silent/Background fetch)")
        
        // توليد ID مؤقت إذا لم يكن موجوداً
        let messageId = (userInfo["gcm.message_id"] as? String) ?? "bg_\(Date().timeIntervalSince1970)"
        
        let notificationData = extractNotificationData(
            from: userInfo,
            identifier: messageId
        )
        
        if sendNotificationToFlutter(notificationData) {
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("🔑 FCM Token: \(String(describing: fcmToken))")
        // Flutter plugin handles token registration usually, but logging helps debug
    }
}