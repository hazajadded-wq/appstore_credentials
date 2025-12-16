import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import UserNotifications

@UIApplicationMain
class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        print("""
        🚀 =================================
        🚀 Starting SalaryInfo App
        🚀 Bundle ID: com.pocket.salaryinfo
        🚀 Firebase Project: scgfs-salary-app
        🚀 =================================
        """)

        // Check for GoogleService-Info.plist
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") == nil {
            print("❌ CRITICAL ERROR: GoogleService-Info.plist not found in bundle!")
        } else {
            print("✅ GoogleService-Info.plist found and loaded")
        }

        // Configure Firebase
        FirebaseApp.configure()
        print("✅ Firebase configured successfully")

        // Setup Firebase Messaging
        Messaging.messaging().delegate = self
        
        // Setup APNs
        setupAPNsAndNotifications(application: application)
        
        // Get FCM Token
        getFCMToken()

        GeneratedPluginRegistrant.register(with: self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func setupAPNsAndNotifications(application: UIApplication) {
        // Request permission
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
        }

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
        
        application.registerForRemoteNotifications()
    }

    private func getFCMToken() {
        Messaging.messaging().token { token, error in
            if let error = error {
                print("❌ Error fetching FCM token: \(error.localizedDescription)")
            } else if let token = token {
                UserDefaults.standard.set(token, forKey: "fcm_token")
                print("✅ FCM Token: \(token)")
            }
        }
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Set APNs token for Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
        
        // Convert token to string for logging
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("✅ APNs Device Token: \(tokenString)")
        
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ APNs Registration FAILED: \(error.localizedDescription)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }
}

// MARK: - Firebase Messaging Delegate
extension AppDelegate: MessagingDelegate {

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        UserDefaults.standard.set(token, forKey: "fcm_token")
        print("🔄 FCM Token refreshed: \(token)")
    }
}