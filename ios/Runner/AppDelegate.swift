import Flutter
import flutter_background_service_ios
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var shareChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    SwiftFlutterBackgroundServicePlugin.taskIdentifier = "dev.flutter.background.refresh"
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    shareChannel = FlutterMethodChannel(
      name: "inneru/native_share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    shareChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareImage",
            let args = call.arguments as? [String: Any],
            let filePath = args["filePath"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }

      let text = args["text"] as? String
      let fileURL = URL(fileURLWithPath: filePath)
      var items: [Any] = [fileURL]
      if let text, !text.isEmpty {
        items.insert(text, at: 0)
      }

      DispatchQueue.main.async {
        guard let host = self?.window?.rootViewController else {
          result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Unable to present share sheet.", details: nil))
          return
        }

        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activityViewController.popoverPresentationController {
          popover.sourceView = host.view
          popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
          popover.permittedArrowDirections = []
        }

        host.present(activityViewController, animated: true) {
          result(nil)
        }
      }
    }
  }
}
