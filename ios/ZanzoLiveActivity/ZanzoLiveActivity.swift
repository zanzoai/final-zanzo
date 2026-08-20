// ZanzoLiveActivity.swift
//
// The Zanzo job-tracking Live Activity: Lock Screen / banner presentation plus
// the Dynamic Island (compact, minimal and expanded). Rendered from the
// shared JobActivityAttributes that the app updates via ActivityKit.
//
// Visual language mirrors the app's AppTheme: warm cream, brown ink, a living
// saffron accent — never cold-blue SaaS.

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Palette (kept in sync with lib/core/theme/app_theme.dart)

private enum Zanzo {
    static let saffron = Color(red: 0xE8 / 255, green: 0x72 / 255, blue: 0x0C / 255)
    static let saffronDeep = Color(red: 0xC8 / 255, green: 0x5D / 255, blue: 0x08 / 255)
    static let ink = Color(red: 0x3B / 255, green: 0x2A / 255, blue: 0x1E / 255)
    static let muted = Color(red: 0x8C / 255, green: 0x7B / 255, blue: 0x6E / 255)
    static let ground = Color(red: 0xFC / 255, green: 0xFA / 255, blue: 0xF6 / 255)
    static let track = Color(red: 0xE8 / 255, green: 0xE2 / 255, blue: 0xD9 / 255)
    static let success = Color(red: 0x16 / 255, green: 0xA3 / 255, blue: 0x4A / 255)
}

// MARK: - Deep link

/// Builds `zanzo://track?jobId=<id>&title=<title>` so a tap opens that task's
/// tracking screen.
@available(iOS 16.1, *)
private func deepLink(_ attributes: JobActivityAttributes) -> URL? {
    var comps = URLComponents()
    comps.scheme = "zanzo"
    comps.host = "track"
    var items: [URLQueryItem] = []
    if !attributes.jobId.isEmpty {
        items.append(URLQueryItem(name: "jobId", value: attributes.jobId))
    }
    if !attributes.taskTitle.isEmpty {
        items.append(URLQueryItem(name: "title", value: attributes.taskTitle))
    }
    comps.queryItems = items.isEmpty ? nil : items
    return comps.url
}

// MARK: - Small shared pieces

@available(iOS 16.1, *)
private struct StageGlyph: View {
    let state: JobActivityAttributes.JobState
    var size: CGFloat = 18

    private var symbol: String {
        if state.isComplete { return "checkmark.circle.fill" }
        switch state.statusRaw {
        case "arrived": return "mappin.circle.fill"
        case "in_progress", "started": return "hammer.circle.fill"
        case "travelling", "traveling", "en_route": return "figure.walk.circle.fill"
        case "assigned": return "person.crop.circle.badge.checkmark"
        default: return "magnifyingglass.circle.fill"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(state.isComplete ? Zanzo.success : Zanzo.saffron)
    }
}

@available(iOS 16.1, *)
private struct ProgressTrack: View {
    let state: JobActivityAttributes.JobState
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Zanzo.track)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: state.isComplete
                                ? [Zanzo.success, Zanzo.success]
                                : [Zanzo.saffron, Zanzo.saffronDeep],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geo.size.width * state.fraction))
            }
        }
        .frame(height: height)
    }
}

/// Live-ticking countdown to the task's end time. Renders natively in the
/// Dynamic Island / Lock Screen without the app pushing updates. Once the
/// deadline passes it flips to a red overtime clock counting UP ("+mm:ss").
@available(iOS 16.1, *)
private struct CountdownText: View {
    let endDate: Date
    var size: CGFloat = 15
    var color: Color = Zanzo.saffron
    /// Hint from the app; we also self-guard on the date so we never form an
    /// invalid `Date()...endDate` range (that crashes the widget) after expiry.
    var overtime: Bool = false

    private var isOvertime: Bool { overtime || endDate <= Date() }

    var body: some View {
        Group {
            if isOvertime {
                HStack(spacing: 1) {
                    Text("+")
                    // Count up from the deadline. Fixed lower bound keeps it
                    // ticking correctly across re-renders.
                    Text(timerInterval: endDate...endDate.addingTimeInterval(24 * 3600),
                         countsDown: false)
                }
                .foregroundStyle(Color.red)
            } else {
                Text(timerInterval: Date()...endDate, countsDown: true)
                    .foregroundStyle(color)
            }
        }
        .font(.system(size: size, weight: .bold).monospacedDigit())
        .multilineTextAlignment(.trailing)
    }
}

/// Small red pill showing the unread crew-message count.
@available(iOS 16.1, *)
private struct UnreadPill: View {
    let count: Int
    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.red))
    }
}

// MARK: - Lock Screen / banner presentation

@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<JobActivityAttributes>

    private var state: JobActivityAttributes.JobState { context.state }

    var body: some View {
        content
            // Tapping the Lock Screen / banner opens this task's tracking screen.
            .widgetURL(deepLink(context.attributes))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                StageGlyph(state: state, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.taskTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Zanzo.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Zanzo.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if state.unreadCount > 0 {
                    UnreadPill(count: state.unreadCount)
                }
                if let end = state.endDate {
                    CountdownText(endDate: end, size: 15, color: Zanzo.ink,
                                  overtime: state.overtime)
                } else {
                    Text("\(min(state.stageIndex + 1, context.attributes.totalStages))/\(context.attributes.totalStages)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Zanzo.saffron)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Zanzo.saffron.opacity(0.12)))
                }
            }
            ProgressTrack(state: state)
        }
        .padding(16)
        .activityBackgroundTint(Zanzo.ground)
        .activitySystemActionForegroundColor(Zanzo.ink)
    }

    private var subtitle: String {
        if let name = state.crewName, !name.isEmpty, !state.isComplete {
            return "\(state.stageLabel) · \(name)"
        }
        return state.stageLabel
    }
}

// MARK: - Widget configuration

@available(iOS 16.1, *)
struct ZanzoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JobActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StageGlyph(state: state, size: 26)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 6) {
                        if state.unreadCount > 0 { UnreadPill(count: state.unreadCount) }
                        if let end = state.endDate {
                            CountdownText(endDate: end, size: 15,
                                          color: state.isComplete ? Zanzo.success : Zanzo.saffron,
                                          overtime: state.overtime)
                        } else {
                            Text("\(min(state.stageIndex + 1, context.attributes.totalStages))/\(context.attributes.totalStages)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(state.isComplete ? Zanzo.success : Zanzo.saffron)
                        }
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.taskTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressTrack(state: state, height: 6)
                        Text(bottomLabel(state))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    StageGlyph(state: state, size: 18)
                    if state.unreadCount > 0 {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                    }
                }
            } compactTrailing: {
                if let end = state.endDate {
                    CountdownText(endDate: end, size: 13,
                                  color: state.isComplete ? Zanzo.success : Zanzo.saffron,
                                  overtime: state.overtime)
                        .frame(maxWidth: 54)
                } else {
                    Text("\(min(state.stageIndex + 1, context.attributes.totalStages))/\(context.attributes.totalStages)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(state.isComplete ? Zanzo.success : Zanzo.saffron)
                }
            } minimal: {
                StageGlyph(state: state, size: 17)
            }
            .widgetURL(deepLink(context.attributes))
            .keylineTint(Zanzo.saffron)
        }
    }

    private func bottomLabel(_ state: JobActivityAttributes.JobState) -> String {
        if let name = state.crewName, !name.isEmpty, !state.isComplete {
            return "\(state.stageLabel) · \(name)"
        }
        return state.stageLabel
    }
}
