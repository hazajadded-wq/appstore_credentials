import Flutter
import UIKit
import WebKit   // ← مهم جداً لتفعيل الويب فيو

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController

    // ================================================================
    // 🔵 1) قناة snapshot لإرسال صورة من WKWebView إلى Flutter
    // ================================================================
    let snapChannel = FlutterMethodChannel(
        name: "snap_webview",
        binaryMessenger: controller.binaryMessenger
    )

    snapChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "takeSnapshot" {

            guard let webView = self.findWKWebView(in: controller.view) else {
                result(FlutterError(code: "NO_WEBVIEW", message: "WKWebView not found", details: nil))
                return
            }

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

    // ================================================================
    // 🔵 2) تفعيل التكبير والتصغير الحقيقي في WKWebView
    // ================================================================
    NotificationCenter.default.addObserver(
        forName: NSNotification.Name("FlutterWebViewCreated"),
        object: nil,
        queue: .main
    ) { notification in
        if let webView = notification.object as? WKWebView {
            webView.scrollView.minimumZoomScale = 1.0
            webView.scrollView.maximumZoomScale = 5.0
            webView.scrollView.zoomScale = 1.0
            webView.scrollView.isMultipleTouchEnabled = true
            webView.scrollView.bouncesZoom = true
        }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ================================================================
  // 🔵 3) دالة للعثور على WKWebView داخل شجرة UIView
  // ================================================================
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
