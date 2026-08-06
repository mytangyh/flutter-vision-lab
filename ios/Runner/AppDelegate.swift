import Darwin
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let didFinishLaunching = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
    registerPlatformChannel()
    return didFinishLaunching
  }

  private func registerPlatformChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "aicamera/platform",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(
          FlutterError(
            code: "APP_DELEGATE_UNAVAILABLE",
            message: "Platform service is unavailable.",
            details: nil
          )
        )
        return
      }
      switch call.method {
      case "getPlatformInfo":
        result(self.platformInfo())
      case "shareJson":
        guard
          let arguments = call.arguments as? [String: Any],
          let json = arguments["json"] as? String
        else {
          result(
            FlutterError(
              code: "INVALID_JSON",
              message: "A JSON string is required.",
              details: nil
            )
          )
          return
        }
        self.share(json: json, from: controller, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func platformInfo() -> [String: Any] {
    return [
      "manufacturer": "Apple",
      "model": machineIdentifier(),
      "operatingSystem": "iOS",
      "systemVersion": UIDevice.current.systemVersion,
      "androidSdk": 0,
      "abi": architectureName(),
    ]
  }

  private func machineIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafeBytes(of: &systemInfo.machine) { buffer in
      let identifier = buffer.prefix { $0 != 0 }
      return String(bytes: identifier, encoding: .utf8) ?? "unknown"
    }
  }

  private func architectureName() -> String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return "unknown"
    #endif
  }

  private func share(
    json: String,
    from controller: UIViewController,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      var presenter = controller
      while let presented = presenter.presentedViewController {
        presenter = presented
      }
      let activityController = UIActivityViewController(
        activityItems: [json],
        applicationActivities: nil
      )
      if let popover = activityController.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(
          x: presenter.view.bounds.midX,
          y: presenter.view.bounds.midY,
          width: 1,
          height: 1
        )
      }
      presenter.present(activityController, animated: true) {
        result(nil)
      }
    }
  }
}
