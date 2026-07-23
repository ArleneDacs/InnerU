import Flutter
import AVFoundation
import flutter_background_service_ios
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var shareChannel: FlutterMethodChannel?
  private var meditationKeepAwakeChannel: FlutterMethodChannel?
  private var meditationFeedbackChannel: FlutterMethodChannel?
  private let meditationSynthesizer = AVSpeechSynthesizer()

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

    meditationKeepAwakeChannel = FlutterMethodChannel(
      name: "inneru/meditation_keep_awake",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    meditationKeepAwakeChannel?.setMethodCallHandler { call, result in
      guard call.method == "setEnabled",
            let args = call.arguments as? [String: Any],
            let enabled = args["enabled"] as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }

      DispatchQueue.main.async {
        UIApplication.shared.isIdleTimerDisabled = enabled
        result(nil)
      }
    }

    meditationFeedbackChannel = FlutterMethodChannel(
      name: "inneru/meditation_feedback",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    meditationFeedbackChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }

      switch call.method {
      case "speak":
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          result(nil)
          return
        }

        DispatchQueue.main.async {
          let session = AVAudioSession.sharedInstance()
          try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
          try? session.setActive(true)
          self.meditationSynthesizer.stopSpeaking(at: .immediate)
          let utterance = AVSpeechUtterance(string: text)
          utterance.voice = AVSpeechSynthesisVoice(
            language: Locale.preferredLanguages.first ?? "en-US"
          )
          utterance.rate = 0.48
          self.meditationSynthesizer.speak(utterance)
          result(nil)
        }
      case "stop":
        DispatchQueue.main.async {
          self.meditationSynthesizer.stopSpeaking(at: .immediate)
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
