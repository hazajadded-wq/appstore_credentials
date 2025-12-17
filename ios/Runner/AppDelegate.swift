import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

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

        // ✅ CRITICAL: Initialize Firebase FIRST (FIXES BLACK SCREEN)
        FirebaseApp.configure()
        print("Firebase configured successfully")

        // ✅ Notification delegate
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
            print("UNUserNotificationCenter delegate set")
        }

        // ✅ Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            } else {
                print("Notification permission granted: \(granted)")
            }
        }

        // ✅ Register for APNs
        application.registerForRemoteNotifications()
        print("Registered for remote notifications")

        // ✅ Firebase Messaging delegate (SAFE here)
        Messaging.messaging().delegate = self

        // ✅ Flutter plugins
        GeneratedPluginRegistrant.register(with: self)
        print("Flutter plugins registered")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - APNs Token
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken

        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs Device Token: \(tokenString)")

        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    // MARK: - Firebase Messaging Token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else {
            print("FCM token is nil")
            return
        }

        print("FCM Token received: \(token)")

        UserDefaults.standard.set(token, forKey: "fcm_token")

        // Subscribe to topic
        Messaging.messaging().subscribe(toTopic: "all_employees") { error in
            if let error = error {
                print("Topic subscription failed: \(error.localizedDescription)")
            } else {
                print("Subscribed to topic: all_employees")
            }
        }
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

    // MARK: - Background / Tap Notification
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("Notification tapped: \(userInfo)")
        completionHandler()
    }

    // MARK: - Silent Notifications
    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("Silent notification received: \(userInfo)")
        completionHandler(.newData)
    }
}
