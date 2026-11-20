import SwiftUI

/// Words for an agent action: the five parts of design D9, in the calm tone of
/// design D7 (no minus numbers, "No problem" at a miss).
enum ActionCopy {
    static func headline(_ action: AgentAction) -> String {
        switch action.kind {
        case .bookComeback: "Booked comeback"
        case .move: "Moved"
        case .shrink: "Shrunk"
        case .addRoutine: "Added routine"
        case .note: action.title ?? "Noted"
        }
    }

    static func symbol(_ action: AgentAction) -> String {
        switch action.kind {
        case .bookComeback: "arrow.uturn.forward.circle"
        case .move: "calendar.badge.clock"
        case .shrink: "arrow.down.right.and.arrow.up.left"
        case .addRoutine: "repeat"
        case .note: "text.bubble"
        }
    }

    /// "Your 12:00 PM walk didn't happen. No problem."
    static func lead(_ action: AgentAction) -> String? {
        guard action.kind == .bookComeback, let before = action.before else { return nil }
        return "Your \(before.start.clock) \(Activity.noun(before.activityType)) didn't happen. No problem."
    }

    /// "12:00 PM, 30 min → 6:30 PM, 15 min", old value struck through.
    static func beforeAfter(_ action: AgentAction) -> Text? {
        switch (action.before, action.after) {
        case let (before?, after?):
            Text("\(Text(before.summary).strikethrough().foregroundStyle(Theme.textMuted)) → \(Text(after.summary).fontWeight(.semibold))")
        case let (nil, after?):
            Text(after.summary).fontWeight(.semibold)
        default:
            nil
        }
    }

    /// Loss-framed points line: "Keep your 40 points: 15 minutes tonight."
    static func keep(_ action: AgentAction, now: Date) -> String? {
        guard action.kind == .bookComeback, let after = action.after, let points = action.points else { return nil }
        return "Keep your \(points) points: \(after.minutes) minutes \(when(after.start, now: now))."
    }

    static func when(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return calendar.component(.hour, from: date) >= 17 ? "tonight" : "today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// VoiceOver reads each action as one sentence (design D12).
    static func spoken(_ action: AgentAction) -> String {
        var parts = [headline(action)]
        if let after = action.after {
            parts.append("\(after.start.clock), \(after.minutes) minutes")
        }
        if action.kind == .bookComeback { parts.append("double points") }
        return parts.joined(separator: ", ") + ". " + action.reason
    }
}
