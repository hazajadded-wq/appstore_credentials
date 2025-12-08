import Flutter
import UIKit
import WebKit

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

            // ابحث عن ال WKWebView داخل شجرة ال UIView
            guard let webView = self.findWKWebView(in: controller.view) else {
                result(FlutterError(code: "NO_WEBVIEW", message: "WKWebView not found", details: nil))
                return
            }

            // استخدم WKWebView snapshot
            webView.takeSnapshot(with: nil) { image, error in
                if let error = error {
                    result(FlutterError(code: "SNAP_ERROR", message: error.localizedDescription, details: nil))
                    return
                }

                guard let uiImage = image,
                      let data = uiImage.pngData() else {
                    result(FlutterError(code: "NO_IMAGE", message: "Snapshot failed", details: nil))
                    return
                }

                result(data)
            }
        }
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // دالة للبحث داخل UIView hierarchy
  func findWKWebView(in view: UIView) -> WKWebView? {
      if let webView = view as? WKWebView {
          return webView
      }
      for sub in view.subviews {
          if let found = findWKWebView(in: sub) {
              return found
          }
      }
      return nil
  }
}
