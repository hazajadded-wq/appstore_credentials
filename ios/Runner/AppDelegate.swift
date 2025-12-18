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

        // Generate plugins for Flutter
        GeneratedPluginRegistrant.register(with: self)

        // Call super implementation
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        
        print("App initialization completed successfully")
        
        return result
    }
    
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