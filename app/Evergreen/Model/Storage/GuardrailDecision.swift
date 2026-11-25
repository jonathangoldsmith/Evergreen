import Foundation
import SwiftData

/// What the person chose for one flagged run: take the swap or keep the plan.
/// Not tied to the story day (eng review D4), so a Sunday swap is still there
/// on Monday. The newest decision for a run key is the one in effect.
@Model
final class GuardrailDecision {
    enum Choice: String, Codable { case accept, keep }

    /// The planned run's matching key (calendar, day, title).
    var runKey: String
    var choiceRaw: String
    var flagKindRaw: String
    var runTitle: String
    var calendarTitle: String
    var runStart: Date
    var runEnd: Date
    var unitRaw: String
    var plannedValue: Double
    var suggestedValue: Double
    var longestValue: Double?
    var keepEasy: Bool
    var createdAt: Date
    /// Undo: the decision stays in the log but no longer applies.
    var undone: Bool = false
    /// The source run moved, was renamed or deleted, so its swap was withdrawn.
    /// Evergreen's own cancel, not the person's Undo (plan item 8).
    var cancelled: Bool = false

    init(run: PlannedRun, flag: GuardrailFlag, choice: Choice, at date: Date) {
        runKey = run.key
        choiceRaw = choice.rawValue
        flagKindRaw = flag.kind.rawValue
        runTitle = run.title
        calendarTitle = run.calendarTitle
        runStart = run.start
        runEnd = run.end
        unitRaw = flag.planned.unit.rawValue
        plannedValue = flag.planned.value
        suggestedValue = flag.suggested.value
        longestValue = flag.longest30?.value
        keepEasy = flag.keepEasy
        createdAt = date
    }

    var choice: Choice { Choice(rawValue: choiceRaw) ?? .keep }
    var flagKind: GuardrailFlag.Kind { GuardrailFlag.Kind(rawValue: flagKindRaw) ?? .spike }
    var unit: RunUnit { RunUnit(rawValue: unitRaw) ?? .minutes }
    var planned: RunSize { RunSize(value: plannedValue, unit: unit) }
    var suggested: RunSize { RunSize(value: suggestedValue, unit: unit) }
    var inEffect: Bool { !undone && !cancelled }

    /// The run as it was when decided, for when the calendar can't be read
    /// (a Lock Screen Undo with the phone locked).
    var plannedRun: PlannedRun {
        PlannedRun(key: runKey, title: runTitle, calendarTitle: calendarTitle, start: runStart, end: runEnd,
                   size: planned, isHard: false, isAllDay: false)
    }

    var flag: GuardrailFlag {
        GuardrailFlag(kind: flagKind, planned: planned, suggested: suggested,
                      longest30: longestValue.map { RunSize(value: $0, unit: unit) },
                      keepEasy: keepEasy, injuryAdjusted: false)
    }
}
