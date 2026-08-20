import Flutter
import UIKit
import Stripe

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    LiveActivityBridge.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "ZanzoLiveActivityBridge")!)
    DeepLinkBridge.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "ZanzoDeepLinkBridge")!)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let stripeHandled = StripeAPI.handleURLCallback(with: url)
    if stripeHandled {
      return true
    }
    // Live Activity / Dynamic Island tap → open the tracked task.
    if DeepLinkBridge.handle(url: url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
