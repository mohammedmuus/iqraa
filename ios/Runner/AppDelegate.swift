import CoreLocation
import CryptoKit
import DeviceCheck
import Flutter
import UIKit
import UserNotifications
import WidgetKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets prayer and dhikr reminders show while the app is open.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    // The hourly group check runs in its own Flutter engine, which needs the plugins too.
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IqraaIntegrity") {
      AppIntegrity.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IqraaHeading") {
      Heading.shared.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IqraaLamp") {
      LampBridge.register(with: registrar.messenger())
    }
  }
}

/// The phone's calibrated compass heading from magnetic north, for the Qibla screen. Heading needs no location permission.
/// Sends [heading, 1] when accurate and [heading, 0] when the compass needs calibrating.
final class Heading: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
  static let shared = Heading()
  private let manager = CLLocationManager()
  private var sink: FlutterEventSink?
  private var channel: FlutterEventChannel?

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterEventChannel(name: "tz.or.iqraa/heading", binaryMessenger: messenger)
    channel.setStreamHandler(self)
    self.channel = channel
    manager.delegate = self
    manager.headingFilter = 1
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard CLLocationManager.headingAvailable() else {
      return FlutterError(code: "unavailable", message: "This phone has no compass", details: nil)
    }
    sink = events
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    matchScreen()
    NotificationCenter.default.addObserver(self, selector: #selector(matchScreen), name: UIDevice.orientationDidChangeNotification, object: nil)
    manager.startUpdatingHeading()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager.stopUpdatingHeading()
    NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
    sink = nil
    return nil
  }

  @objc private func matchScreen() {
    switch UIDevice.current.orientation {
    case .landscapeLeft: manager.headingOrientation = .landscapeLeft
    case .landscapeRight: manager.headingOrientation = .landscapeRight
    case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
    case .portrait: manager.headingOrientation = .portrait
    default: break
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    let accurate = newHeading.headingAccuracy >= 0 && newHeading.headingAccuracy <= 15
    sink?([newHeading.magneticHeading, accurate ? 1.0 : 0.0])
  }

  func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
    return true
  }
}

/// Hands the home screen lamp its data through the shared app group, then asks the widget to redraw.
final class LampBridge {
  private static var channel: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "tz.or.iqraa/widget", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "update", let json = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      UserDefaults(suiteName: "group.tz.or.iqraa")?.set(json, forKey: "lamp")
      WidgetCenter.shared.reloadAllTimelines()
      result(nil)
    }
    self.channel = channel
  }
}

/// App Attest: a fresh key is attested for each sensitive request so the server can confirm the genuine app.
final class AppIntegrity {
  private static var channel: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "tz.or.iqraa/integrity", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "token" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any], let nonce = arguments["nonce"] as? String else {
        result(FlutterError(code: "nonce", message: "Missing nonce", details: nil))
        return
      }
      attest(nonce: nonce, result: result)
    }
    self.channel = channel
  }

  private static func attest(nonce: String, result: @escaping FlutterResult) {
    let service = DCAppAttestService.shared
    guard service.isSupported else {
      result(FlutterError(code: "unsupported", message: "App Attest is not available on this device", details: nil))
      return
    }
    let clientDataHash = Data(SHA256.hash(data: Data(nonce.utf8)))
    service.generateKey { keyId, error in
      guard let keyId = keyId, error == nil else {
        DispatchQueue.main.async { result(FlutterError(code: "key", message: error?.localizedDescription, details: nil)) }
        return
      }
      service.attestKey(keyId, clientDataHash: clientDataHash) { attestation, error in
        DispatchQueue.main.async {
          guard let attestation = attestation, error == nil else {
            result(FlutterError(code: "attest", message: error?.localizedDescription, details: nil))
            return
          }
          result(["kind": "attest", "key_id": keyId, "data": attestation.base64EncodedString()])
        }
      }
    }
  }
}
