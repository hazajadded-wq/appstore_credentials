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
        🚀 =================================
        🚀 SalaryInfo App Launching
        🚀 Bundle ID: com.pocket.salaryinfo
        🚀 Firebase Project: scgfs-salary-app
        🚀 =================================
        """)
        
        // 1. Check if GoogleService-Info.plist exists
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") == nil {
            print("❌ CRITICAL ERROR: GoogleService-Info.plist not found in bundle!")
        } else {
            print("✅ GoogleService-Info.plist found")
        }
        
        // 2. Setup notification center FIRST (before anything else)
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
            print("✅ UNUserNotificationCenter delegate set")
        }
        
        // 3. Request notification permissions
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in
                if let error = error {
                    print("❌ APNs permission error: \(error.localizedDescription)")
                } else {
                    print("✅ APNs permission granted: \(granted)")
                }
            }
        )
        
        // 4. Register for remote notifications
        application.registerForRemoteNotifications()
        print("✅ Registered for remote notifications")
        
        // 5. Setup Firebase Messaging delegate
        // ⚠️ IMPORTANT: DO NOT call FirebaseApp.configure() here
        // Let FlutterFire handle Firebase initialization
        Messaging.messaging().delegate = self
        print("✅ Firebase Messaging delegate set")
        
        // 6. Call super to setup Flutter
        GeneratedPluginRegistrant.register(with: self)
        print("✅ Flutter plugins registered")
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - APNs Token Handling
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Pass device token to Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
        
        // Convert token to string for logging
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("✅ APNs Device Token: \(tokenString)")
        
        // Call super
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ APNs Registration FAILED: \(error.localizedDescription)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }
    
    // MARK: - Notification Handling (Foreground)
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        print("📱 Will present notification (app in foreground): \(userInfo)")
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("📱 Did receive notification response (app opened from notification): \(userInfo)")
        completionHandler()
    }
    
    // MARK: - Handle Silent Notifications
    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📱 Received remote notification (silent): \(userInfo)")
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
        
        print("🔄 FCM Token: \(token)")
        
        // Store token for later use
        UserDefaults.standard.set(token, forKey: "fcm_token")
        
        // Subscribe to topic
        Messaging.messaging().subscribe(toTopic: "all_employees") { error in
            if let error = error {
                print("❌ Failed to subscribe to topic: \(error.localizedDescription)")
            } else {
                print("✅ Subscribed to topic: all_employees")
            }
        }
    }
}