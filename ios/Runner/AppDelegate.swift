import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import UserNotifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // 🔥 1. Configure Firebase FIRST
        print("""
        🚀 =================================
        🚀 Starting SalaryInfo App
        🚀 Bundle ID: com.pocket.salaryinfo
        🚀 Firebase Project: scgfs-salary-app
        🚀 =================================
        """)
        
        // Check for Firebase config file
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") == nil {
            print("❌ CRITICAL ERROR: GoogleService-Info.plist not found in bundle!")
            print("ℹ️ Make sure the file is in ios/Runner/ directory")
        } else {
            print("✅ GoogleService-Info.plist found and loaded")
        }
        
        // Initialize Firebase
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("✅ Firebase configured successfully")
        } else {
            print("✅ Firebase already configured")
        }
        
        // 🔥 2. Setup Firebase Messaging with APNs
        print("📱 Setting up Firebase Messaging with APNs...")
        Messaging.messaging().delegate = self
        
        // 🔥 3. Configure APNs and Notifications
        setupAPNsAndNotifications(application: application)
        
        // 🔥 4. Get FCM Token
        getFCMToken()
        
        // 🔥 5. Register Flutter plugins
        GeneratedPluginRegistrant.register(with: self)
        print("✅ All Flutter plugins registered")
        
        print("""
        ✅ =================================
        ✅ App Initialization Complete
        ✅ Ready to launch Flutter Engine
        ✅ =================================
        """)
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - APNs & Notifications Setup
    private func setupAPNsAndNotifications(application: UIApplication) {
        print("🔔 Configuring APNs and Notifications...")
        
        // Set UNUserNotificationCenter delegate
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
            print("✅ UNUserNotificationCenter delegate set")
        }
        
        // Request notification permissions
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
                return
            }
            
            if granted {
                print("✅ Notification permission GRANTED by user")
                
                // Get notification settings
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    print("📊 Notification Settings:")
                    print("   - Authorization Status: \(settings.authorizationStatus.rawValue)")
                    print("   - Sound: \(settings.soundSetting == .enabled ? "Enabled" : "Disabled")")
                    print("   - Badge: \(settings.badgeSetting == .enabled ? "Enabled" : "Disabled")")
                    print("   - Alert: \(settings.alertSetting == .enabled ? "Enabled" : "Disabled")")
                }
            } else {
                print("⚠️ Notification permission DENIED by user")
            }
        }
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        print("✅ Registered for remote notifications")
    }
    
    // MARK: - FCM Token Management
    private func getFCMToken() {
        print("🔑 Fetching FCM Token...")
        
        Messaging.messaging().token { token, error in
            if let error = error {
                print("❌ Error fetching FCM token: \(error.localizedDescription)")
                print("ℹ️ This might be due to:")
                print("   1. Missing GoogleService-Info.plist")
                print("   2. Invalid Firebase configuration")
                print("   3. Network issues")
            } else if let token = token {
                print("✅ FCM Token received successfully")
                print("📱 Token: \(token)")
                
                // Store token locally
                UserDefaults.standard.set(token, forKey: "fcm_token")
                print("💾 FCM Token saved to UserDefaults")
                
                // Send to server if needed (uncomment and implement)
                // self.sendTokenToServer(fcmToken: token)
            }
        }
    }
    
    // MARK: - APNs Token Handling
    override func application(_ application: UIApplication,
                             didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("✅ APNs Device Token received successfully")
        
        // Convert token to string for logging
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 APNs Token (first 20 chars): \(String(tokenString.prefix(20)))...")
        
        // Set APNs token for Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
        print("🔗 APNs token linked to Firebase Messaging")
        
        // Store token locally
        UserDefaults.standard.set(tokenString, forKey: "apns_token")
        print("💾 APNs Token saved to UserDefaults")
        
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    override func application(_ application: UIApplication,
                             didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ APNs Registration FAILED: \(error.localizedDescription)")
        print("⚠️ Possible causes:")
        print("   1. APNs Authentication Key not configured in Firebase Console")
        print("   2. Invalid APNs certificate")
        print("   3. App not properly provisioned for push notifications")
        print("   4. Missing 'remote-notification' in UIBackgroundModes")
        
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }
}

// MARK: - MessagingDelegate Extension
extension AppDelegate: MessagingDelegate {
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("🔄 FCM Registration Token refreshed")
        
        guard let fcmToken = fcmToken else {
            print("⚠️ Received nil FCM token on refresh")
            return
        }
        
        print("🆕 New FCM Token: \(fcmToken)")
        
        // Update stored token
        UserDefaults.standard.set(fcmToken, forKey: "fcm_token")
        print("💾 Updated FCM Token saved")
        
        // Send to your server (implement this if needed)
        sendTokenToServer(fcmToken: fcmToken)
    }
    
    private func sendTokenToServer(fcmToken: String) {
        // Implement this method to send token to your backend server
        print("📤 [Server] Would send FCM token to backend: \(fcmToken)")
        
        // Example implementation:
        /*
        guard let url = URL(string: "https://your-server.com/register-fcm-token") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "token": fcmToken,
            "platform": "ios",
            "bundle_id": Bundle.main.bundleIdentifier ?? "unknown",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Failed to send token to server: \(error)")
                return
            }
            print("✅ Token sent to server successfully")
        }.resume()
        */
    }
}

// MARK: - UNUserNotificationCenterDelegate Extension
@available(iOS 10, *)
extension AppDelegate: UNUserNotificationCenterDelegate {
    
    // Handle notification when app is in FOREGROUND
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        
        print("📱 Notification received in FOREGROUND")
        print("📦 Notification data: \(userInfo)")
        
        // Extract notification details
        if let aps = userInfo["aps"] as? [String: Any] {
            print("📊 APS Payload: \(aps)")
        }
        
        // Show notification with banner, sound, and badge
        completionHandler([[.banner, .sound, .badge]])
    }
    
    // Handle notification tap (when user taps notification)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        print("👆 Notification TAPPED by user")
        print("📦 Notification data: \(userInfo)")
        
        // Handle deep linking or navigation based on notification
        handleNotificationTap(userInfo: userInfo)
        
        completionHandler()
    }
    
    private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        print("🔗 Processing notification tap...")
        
        // Extract deep link or action from notification
        if let deepLink = userInfo["deep_link"] as? String {
            print("🌐 Deep link found: \(deepLink)")
            // Navigate to specific screen
            // You can use Flutter MethodChannel to communicate with Flutter
        }
        
        if let screen = userInfo["screen"] as? String {
            print("📱 Navigate to screen: \(screen)")
            // Handle navigation to specific screen
        }
        
        // You can add more custom handling here
    }
}