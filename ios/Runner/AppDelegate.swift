import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate {

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

        // ✅ CRITICAL: Firebase init (FIXES BLACK SCREEN)
        FirebaseApp.configure()
        print("Firebase configured")

        // ✅ Notification delegate (FlutterAppDelegate already conforms)
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
        }

        // ✅ Request permission
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            } else {
                print("Notification permission granted: \(granted)")
            }
        }

        // ✅ APNs
        application.registerForRemoteNotifications()

        // ✅ Firebase Messaging delegate
        Messaging.messaging().delegate = self

        // ✅ Flutter plugins
        GeneratedPluginRegistrant.register(with: self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - APNs Token
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken

        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs token: \(tokenString)")

        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNs registration failed: \(error.localizedDescription)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    // MARK: - FCM Token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else {
            print("FCM token is nil")
            return
        }

        print("FCM token received: \(token)")
        UserDefaults.standard.set(token, forKey: "fcm_token")

        Messaging.messaging().subscribe(toTopic: "all_employees")
    }

    // MARK: - Foreground Notification
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    // MARK: - Notification Tap
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("Notification tapped")
        completionHandler()
    }

    // MARK: - Silent Notification
    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("Silent notification received")
        completionHandler(.newData)
    }
}
