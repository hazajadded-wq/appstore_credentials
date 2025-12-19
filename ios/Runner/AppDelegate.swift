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
        EMERGENCY MINIMAL VERSION
        NO FIREBASE - NO NOTIFICATIONS
        ================================
        """)
        
        // ✅ EMERGENCY FIX: No Firebase, no notifications
        // Just register Flutter plugins and return
        
        GeneratedPluginRegistrant.register(with: self)
        print("✅ Flutter plugins registered")
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}