import UIKit
import Flutter

@available(iOS 13.0, *)
class SceneDelegate: FlutterSceneDelegate {
    override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        
        // Set white background to prevent black screen
        if let window = self.window {
            window.backgroundColor = UIColor.white
        }
        
        // Call super implementation
        super.scene(scene, willConnectTo: session, options: connectionOptions)
    }
}