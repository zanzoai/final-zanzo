// DeepLinkBridge.swift
//
// Forwards `zanzo://track?jobId=…&title=…` deep links (opened by tapping the
// Live Activity / Dynamic Island) into Flutter over the "zanzo/deeplink"
// MethodChannel.
//
// Two delivery paths so it works both warm and cold:
//   • Warm: AppDelegate calls handle(url:) → we invoke Dart "onDeepLink".
//   • Cold: the URL arrives before the Dart handler is ready, so we stash it
//     and Dart drains it via "getInitialLink" on startup.

import Flutter
import Foundation

enum DeepLinkBridge {
    static let channelName = "zanzo/deeplink"

    private static var channel: FlutterMethodChannel?
    private static var pendingLink: [String: String]?

    static func register(with registrar: FlutterPluginRegistrar) {
        let ch = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        ch.setMethodCallHandler { call, result in
            switch call.method {
            case "getInitialLink":
                result(pendingLink)
                pendingLink = nil
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        channel = ch
    }

    /// Returns true if the URL was a Zanzo deep link we handled.
    @discardableResult
    static func handle(url: URL) -> Bool {
        guard url.scheme == "zanzo", url.host == "track" else { return false }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var payload: [String: String] = [:]
        if let jobId = comps?.queryItems?.first(where: { $0.name == "jobId" })?.value {
            payload["jobId"] = jobId
        }
        if let title = comps?.queryItems?.first(where: { $0.name == "title" })?.value {
            payload["title"] = title
        }

        // Deliver now if Dart is listening; always stash as a fallback for cold
        // start (Dart clears it via getInitialLink).
        pendingLink = payload
        channel?.invokeMethod("onDeepLink", arguments: payload)
        return true
    }
}
