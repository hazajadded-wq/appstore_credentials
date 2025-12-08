import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    let snapChannel = FlutterMethodChannel(
        name: "snap_webview",
        binaryMessenger: controller.binaryMessenger
    )
    
    snapChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "takeSnapshot" {
            
            guard let rootView = controller.view else {
                result(FlutterError(code: "NO_VIEW", message: "Root view not found", details: nil))
                return
            }
            
            // أخذ صورة للشاشة بما فيها WebView
            UIGraphicsBeginImageContextWithOptions(
                rootView.bounds.size,
                false,
                UIScreen.main.scale
            )
            
            rootView.drawHierarchy(in: rootView.bounds, afterScreenUpdates: true)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let uiImage = image, let data = uiImage.pngData() {
                result(data)
            } else {
                result(FlutterError(code: "SNAP_ERROR", message: "Snapshot failed", details: nil))
            }
            
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
