import Flutter
import AVFoundation
import flutter_background_service_ios
import HealthKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var shareChannel: FlutterMethodChannel?
  private var appleHealthChannel: FlutterMethodChannel?
  private var meditationKeepAwakeChannel: FlutterMethodChannel?
  private var meditationFeedbackChannel: FlutterMethodChannel?
  private let meditationSynthesizer = AVSpeechSynthesizer()
  private let healthStore = HKHealthStore()

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
        guard let host = self?.sharePresenterViewController() else {
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

    appleHealthChannel = FlutterMethodChannel(
      name: "inneru/apple_health",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    appleHealthChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }

      switch call.method {
      case "readTodaySteps":
        self.readTodayHealthSteps(result: result)
      case "requestStepsAccess":
        self.requestStepHealthAccess(result: result)
      case "openHealthApp":
        self.openHealthApp(result: result)
      default:
        result(FlutterMethodNotImplemented)
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

  private func sharePresenterViewController() -> UIViewController? {
    let activeScene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let sceneWindow = activeScene?.windows.first { $0.isKeyWindow }
    let root = sceneWindow?.rootViewController ?? window?.rootViewController
    return topViewController(from: root)
  }

  private func topViewController(from root: UIViewController?) -> UIViewController? {
    if let presented = root?.presentedViewController {
      return topViewController(from: presented)
    }
    if let navigation = root as? UINavigationController {
      return topViewController(from: navigation.visibleViewController)
    }
    if let tab = root as? UITabBarController {
      return topViewController(from: tab.selectedViewController)
    }
    return root
  }

  private func openHealthApp(result: @escaping FlutterResult) {
    let healthURLs = [
      "x-apple-health://",
      "x-apple-health:",
      "x-argonaut-app://",
      "x-argonaut-app:"
    ].compactMap { URL(string: $0) }

    DispatchQueue.main.async {
      func openNext(_ index: Int) {
        guard index < healthURLs.count else {
          result(false)
          return
        }

        UIApplication.shared.open(healthURLs[index], options: [:]) { opened in
          if opened {
            result(true)
          } else {
            openNext(index + 1)
          }
        }
      }

      openNext(0)
    }
  }

  private func requestStepHealthAccess(result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable(),
          let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
      result(FlutterError(code: "HEALTH_UNAVAILABLE", message: "Apple Health is not available on this device.", details: nil))
      return
    }

    healthStore.requestAuthorization(toShare: [], read: [stepType]) { granted, error in
      if let error {
        result(FlutterError(code: "HEALTH_AUTH_FAILED", message: error.localizedDescription, details: nil))
        return
      }

      result(granted)
    }
  }

  private func readTodayHealthSteps(result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable(),
          let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
      result(FlutterError(code: "HEALTH_UNAVAILABLE", message: "Apple Health is not available on this device.", details: nil))
      return
    }

    healthStore.requestAuthorization(toShare: [], read: [stepType]) { [weak self] granted, error in
      if let error {
        result(FlutterError(code: "HEALTH_AUTH_FAILED", message: error.localizedDescription, details: nil))
        return
      }

      guard granted else {
        result(FlutterError(code: "HEALTH_PERMISSION_DENIED", message: "Apple Health step access was not granted.", details: nil))
        return
      }

      let calendar = Calendar.current
      let startOfDay = calendar.startOfDay(for: Date())
      let predicate = HKQuery.predicateForSamples(
        withStart: startOfDay,
        end: Date(),
        options: [.strictStartDate]
      )

      let query = HKStatisticsQuery(
        quantityType: stepType,
        quantitySamplePredicate: predicate,
        options: .cumulativeSum
      ) { _, statistics, error in
        if let error {
          self?.readTodayHealthStepsBySamples(
            stepType: stepType,
            predicate: predicate,
            originalError: error,
            result: result
          )
          return
        }

        let steps = statistics?
          .sumQuantity()?
          .doubleValue(for: HKUnit.count()) ?? 0
        result(Int(steps.rounded()))
      }

      self?.healthStore.execute(query)
    }
  }

  private func readTodayHealthStepsBySamples(
    stepType: HKQuantityType,
    predicate: NSPredicate,
    originalError: Error,
    result: @escaping FlutterResult
  ) {
    let query = HKSampleQuery(
      sampleType: stepType,
      predicate: predicate,
      limit: HKObjectQueryNoLimit,
      sortDescriptors: nil
    ) { _, samples, sampleError in
      if let sampleError {
        result(FlutterError(
          code: "HEALTH_QUERY_FAILED",
          message: sampleError.localizedDescription,
          details: ["statisticsError": originalError.localizedDescription]
        ))
        return
      }

      let steps = (samples as? [HKQuantitySample])?
        .reduce(0.0) { total, sample in
          total + sample.quantity.doubleValue(for: HKUnit.count())
        } ?? 0
      result(Int(steps.rounded()))
    }

    healthStore.execute(query)
  }
}
