import UIKit
import Flutter

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
        Mode: CRASH-FREE (Firebase in Dart)
        Version: 1.0.12 Build 8
        ================================
        """)

        // CRITICAL: Generate plugins for Flutter
        GeneratedPluginRegistrant.register(with: self)

        // Call super implementation
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        
        print("App initialization completed successfully")
        
        return result
    }
    
    // MARK: - Scene Configuration (iOS 13+)
    @available(iOS 13.0, *)
    override func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    // MARK: - Remote Notifications
    override func application(_ application: UIApplication,
                             didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("📱 Device token received: \(deviceToken)")
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    override func application(_ application: UIApplication,
                             didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }
    
    // MARK: - Lifecycle Methods
    override func applicationDidEnterBackground(_ application: UIApplication) {
        print("App entered background")
        super.applicationDidEnterBackground(application)
    }
    
    override func applicationWillEnterForeground(_ application: UIApplication) {
        print("App will enter foreground")
        super.applicationWillEnterForeground(application)
    }
    
    override func applicationDidBecomeActive(_ application: UIApplication) {
        print("App became active")
        super.applicationDidBecomeActive(application)
    }
    
    override func applicationWillTerminate(_ application: UIApplication) {
        print("App will terminate")
        super.applicationWillTerminate(application)
    }
}