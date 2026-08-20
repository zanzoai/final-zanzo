// JobActivityAttributes.swift
//
// Shared shape for the Zanzo job-tracking Live Activity.
// This file is a member of BOTH the Runner app target (which starts/updates
// the activity via ActivityKit) and the ZanzoLiveActivity widget extension
// (which renders it). Keep it dependency-free so both targets can compile it.

import ActivityKit
import Foundation

@available(iOS 16.1, *)
public struct JobActivityAttributes: ActivityAttributes {
    public typealias ContentState = JobState

    // ── Static: fixed for the life of the activity ───────────────────────────
    /// The errand the user requested, e.g. "Pick up parcel from the post office".
    public let taskTitle: String
    /// Total number of stages in the journey (Finding … Completed).
    public let totalStages: Int
    /// Backend job id — used to deep-link the tap target to this task's screen.
    public let jobId: String

    public init(taskTitle: String, totalStages: Int, jobId: String) {
        self.taskTitle = taskTitle
        self.totalStages = totalStages
        self.jobId = jobId
    }

    // ── Dynamic: updated as the job progresses ──────────────────────────────
    public struct JobState: Codable, Hashable {
        /// 0-based current stage index (0 = finding crew … totalStages-1 = done).
        public let stageIndex: Int
        /// Human label for the current stage, e.g. "Agent is travelling".
        public let stageLabel: String
        /// Raw backend status (assigned/travelling/arrived/in_progress/completed…).
        public let statusRaw: String
        /// Assigned crew member's name once known; nil while still searching.
        public let crewName: String?
        /// Unread chat messages from the crew (0 = none).
        public let unreadCount: Int
        /// When set (>0), the task countdown end time as Unix epoch seconds; the
        /// widget renders a live-ticking countdown to it. nil/0 = no countdown.
        public let endEpoch: Double?
        /// True once the scheduled end has passed — the widget then counts UP in
        /// red (overtime) instead of down. Set by the app when it crosses the
        /// deadline so ActivityKit re-renders; the widget also self-guards on
        /// endDate so it never forms an invalid past countdown range.
        public let overtime: Bool

        public init(
            stageIndex: Int,
            stageLabel: String,
            statusRaw: String,
            crewName: String?,
            unreadCount: Int = 0,
            endEpoch: Double? = nil,
            overtime: Bool = false
        ) {
            self.stageIndex = stageIndex
            self.stageLabel = stageLabel
            self.statusRaw = statusRaw
            self.crewName = crewName
            self.unreadCount = unreadCount
            self.endEpoch = endEpoch
            self.overtime = overtime
        }

        /// The countdown end as a Date, if an active countdown is set.
        public var endDate: Date? {
            guard let e = endEpoch, e > 0 else { return nil }
            return Date(timeIntervalSince1970: e)
        }

        /// Progress 0.0…1.0 across the journey.
        public var fraction: Double {
            guard stageIndex > 0 else { return 0.04 } // show a sliver at the start
            let denom = Double(max(totalStagesFallback - 1, 1))
            return min(1.0, Double(stageIndex) / denom)
        }

        /// The activity is finished once the job is completed/settled.
        public var isComplete: Bool {
            statusRaw == "completed" || statusRaw == "settled"
        }

        // ContentState can't see the static attributes, so fall back to the
        // known Zanzo journey length (6 stages) for the progress denominator.
        private var totalStagesFallback: Int { 6 }
    }
}
