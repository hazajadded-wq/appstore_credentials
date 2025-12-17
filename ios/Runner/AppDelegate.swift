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
        ================================
        SalaryInfo App Launching
        Bundle ID: com.pocket.salaryinfo
        Firebase Project: scgfs-salary-app
        ================================
        """)
        
        // 1. Check if GoogleService-Info.plist exists
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") == nil {
            print("CRITICAL ERROR: GoogleService-Info.plist not found in bundle!")
        } else {
            print("GoogleService-Info.plist found")
        }
        
        // 2. Setup notification center FIRST (before anything else)
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
            print("UNUserNotificationCenter delegate set")
        }
        
        // 3. Request notification permissions
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in
                if let error = error {
                    print("APNs permission error: \(error.localizedDescription)")
                } else {
                    print("APNs permission granted: \(granted)")
                }
            }
        )
        
        // 4. Register for remote notifications
        application.registerForRemoteNotifications()
        print("Registered for remote notifications")
        
        // 5. ✅ CRITICAL FIX: DO NOT set up Firebase Messaging delegate here!
        // Let Flutter initialize Firebase first, then set up the delegate
        // The old line that was causing the crash:
        // Messaging.messaging().delegate = self  // ❌ REMOVED - This was causing the crash
        
        // 6. Call super to setup Flutter
        GeneratedPluginRegistrant.register(with: self)
        print("Flutter plugins registered")
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - APNs Token Handling
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Only set APNs token if Firebase is already initialized
        if FirebaseApp.app() != nil {
            Messaging.messaging().apnsToken = deviceToken
            print("APNs token set to Firebase Messaging")
        } else {
            // Store the token temporarily and set it later when Firebase is ready
            UserDefaults.standard.set(deviceToken, forKey: "pending_apns_token")
            print("APNs token stored for later Firebase setup")
        }
        
        // Convert token to string for logging
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs Device Token: \(tokenString)")
        
        // Call super
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNs Registration FAILED: \(error.localizedDescription)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }
    
    // MARK: - Notification Handling (Foreground)
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        print("Will present notification (app in foreground): \(userInfo)")
        
        // Show notification even when app is in foreground
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("Did receive notification response (app opened from notification): \(userInfo)")
        completionHandler()
    }
    
    // MARK: - Handle Silent Notifications
    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("Received remote notification (silent): \(userInfo)")
        completionHandler(.newData)
    }
}

// MARK: - Firebase Messaging Delegate
// ✅ This extension will be used AFTER Flutter initializes Firebase
extension AppDelegate: MessagingDelegate {
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else {
            print("No FCM token received")
            return
        }
        
        print("FCM Token received: \(token.prefix(20))...")
        
        // Store token for later use
        UserDefaults.standard.set(token, forKey: "fcm_token")
        
        // Check if we have a pending APNs token to set
        if let pendingTokenData = UserDefaults.standard.object(forKey: "pending_apns_token") as? Data {
            Messaging.messaging().apnsToken = pendingTokenData
            UserDefaults.standard.removeObject(forKey: "pending_apns_token")
            print("Set pending APNs token to Firebase Messaging")
        }
        
        // Subscribe to topic
        Messaging.messaging().subscribe(toTopic: "all_employees") { error in
            if let error = error {
                print("Failed to subscribe to topic: \(error.localizedDescription)")
            } else {
                print("Subscribed to topic: all_employees")
            }
        }
    }
}