// LiveActivityBridge.swift
//
// Bridges Flutter <-> ActivityKit for the Zanzo job-tracking Live Activity.
// Flutter calls over the "zanzo/live_activity" MethodChannel:
//   • start(taskTitle, totalStages, stageIndex, stageLabel, statusRaw, crewName?)
//   • update(stageIndex, stageLabel, statusRaw, crewName?)
//   • end(stageIndex, stageLabel, statusRaw, crewName?)  // dismisses shortly after
//   • isActive() -> Bool
//   • areEnabled() -> Bool
//
// The app starts and updates the activity in-process via ActivityKit, so no
// App Group or push entitlement is required — works on a personal signing team.

import Flutter
import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

enum LiveActivityBridge {
    static let channelName = "zanzo/live_activity"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { call, result in
            handle(call, result: result)
        }
    }

    // Track the current activity so update/end can target it.
    @available(iOS 16.2, *)
    private static var current: Activity<JobActivityAttributes>? {
        get { _currentBox as? Activity<JobActivityAttributes> }
        set { _currentBox = newValue }
    }
    private static var _currentBox: Any?

    private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.2, *) else {
            // Live Activities need iOS 16.1+. Degrade gracefully.
            switch call.method {
            case "areEnabled", "isActive": result(false)
            default: result(nil)
            }
            return
        }

        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "areEnabled":
            result(ActivityAuthorizationInfo().areActivitiesEnabled)

        case "isActive":
            result(current != nil)

        case "start":
            start(args, result: result)

        case "update":
            update(args, result: result)

        case "end":
            end(args, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @available(iOS 16.2, *)
    private static func stateFrom(_ args: [String: Any]) -> JobActivityAttributes.JobState {
        let end = args["endEpoch"] as? Double
        return JobActivityAttributes.JobState(
            stageIndex: (args["stageIndex"] as? Int) ?? 0,
            stageLabel: (args["stageLabel"] as? String) ?? "",
            statusRaw: (args["statusRaw"] as? String) ?? "",
            crewName: (args["crewName"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            unreadCount: (args["unreadCount"] as? Int) ?? 0,
            endEpoch: (end ?? 0) > 0 ? end : nil,
            overtime: (args["overtime"] as? Bool) ?? false
        )
    }

    @available(iOS 16.2, *)
    private static func start(_ args: [String: Any], result: @escaping FlutterResult) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            result(FlutterError(code: "disabled", message: "Live Activities are not enabled", details: nil))
            return
        }
        // If one is already running, update it instead of stacking a second.
        if current != nil {
            update(args, result: result)
            return
        }
        let attributes = JobActivityAttributes(
            taskTitle: (args["taskTitle"] as? String) ?? "Your Zanzo task",
            totalStages: (args["totalStages"] as? Int) ?? 6,
            jobId: (args["jobId"] as? String) ?? ""
        )
        let state = stateFrom(args)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            current = activity
            result(activity.id)
        } catch {
            result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
        }
    }

    @available(iOS 16.2, *)
    private static func update(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let activity = current else {
            result(false)
            return
        }
        let state = stateFrom(args)
        Task {
            await activity.update(.init(state: state, staleDate: nil))
            result(true)
        }
    }

    @available(iOS 16.2, *)
    private static func end(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let activity = current else {
            result(false)
            return
        }
        let state = stateFrom(args)
        current = nil
        Task {
            // Show the final (completed) state briefly, then dismiss.
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 8))
            result(true)
        }
    }
}
