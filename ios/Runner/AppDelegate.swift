import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // APNs registration outcome, read from Dart over "merr/apns" for push
  // diagnostics. firebase_messaging only NSLogs a registration failure, so
  // Apple's actual error would otherwise never be visible.
  private var apnsStatus: [String: Any] = ["state": "pending"]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "MerrApnsDiagnostics") {
      let channel = FlutterMethodChannel(name: "merr/apns", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(nil)
          return
        }
        switch call.method {
        case "status":
          var status = self.apnsStatus
          status["is_registered"] = UIApplication.shared.isRegisteredForRemoteNotifications
          status["profile_aps_environment"] = AppDelegate.profileApsEnvironment()
          result(status)
        case "register":
          UIApplication.shared.registerForRemoteNotifications()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    apnsStatus = ["state": "registered", "token_prefix": String(hex.prefix(12))]
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let nsError = error as NSError
    apnsStatus = [
      "state": "failed",
      "error": nsError.localizedDescription,
      "error_code": nsError.code,
      "error_domain": nsError.domain,
    ]
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  /// aps-environment in the embedded provisioning profile: "production",
  /// "development", "missing" (profile without push) or "no_profile".
  private static func profileApsEnvironment() -> String {
    guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
          let data = FileManager.default.contents(atPath: path),
          let text = String(data: data, encoding: .isoLatin1) else {
      return "no_profile"
    }
    guard let key = text.range(of: "<key>aps-environment</key>") else { return "missing" }
    let rest = text[key.upperBound...]
    guard let open = rest.range(of: "<string>"),
          let close = rest.range(of: "</string>"),
          open.upperBound <= close.lowerBound else {
      return "present"
    }
    return String(rest[open.upperBound..<close.lowerBound])
  }
}
