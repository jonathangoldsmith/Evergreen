import Foundation
import SwiftData

/// The weekly pain check-in (plan item 17) and its OSTRC questions (BN1).
extension AppModel {
    func painRecord(for week: Date) -> PainRecord? {
        painRecords.last { $0.weekStart == week }
    }

    /// The week asked about right now (Sunday 6 PM to Tuesday night), if not answered yet.
    var pendingPainWeek: Date? {
        guard onboarded, let week = PainWeek.openWeek(at: now, calendar: calendar), painRecord(for: week) == nil
        else { return nil }
        return week
    }

    /// Records the one-tap answer at once. "No" is an OSTRC week with no
    /// problem. "A little" and "Yes" open the OSTRC questions. A "Yes" also
    /// sets the injury month to this month (X9).
    func answerPain(_ answer: PainAnswer, week: Date) {
        let record = painRecord(for: week) ?? {
            let new = PainRecord(weekStart: week, answer: answer, at: Date())
            context.insert(new)
            return new
        }()
        record.answerRaw = answer.rawValue
        record.createdAt = Date()
        record.ostrc = answer == .no ? OSTRC.noProblem : record.ostrc
        if answer == .yes {
            profile.injuryMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            profile.injuryAnswered = true
        }
        ostrcWeek = answer.asksOSTRC ? week : nil
        save()
        upload(.pain(answer, ostrc: record.ostrc, week: week, at: Date(), calendar: calendar), ownAnswer: true)
        if answer == .yes { upload(.injury(month: profile.injuryMonth, at: Date(), calendar: calendar), ownAnswer: true) }
        track(.painCheckIn(answered: true))
    }

    /// The four OSTRC answers, and where it hurts after a "Yes". Both stay
    /// optional: a skipped sheet keeps the one-tap answer.
    func saveOSTRC(_ codes: [Int]?, bodyPart: String?, week: Date) {
        guard let record = painRecord(for: week) else { return }
        if let codes, codes.count == OSTRC.questions.count { record.ostrc = codes }
        if let bodyPart { record.bodyPart = bodyPart }
        ostrcWeek = nil
        save()
        // The body part stays on the phone; only the OSTRC answers go up.
        if let ostrc = record.ostrc {
            upload(.pain(record.answer, ostrc: ostrc, week: week, at: Date(), calendar: calendar), ownAnswer: true)
        }
    }

    func skipOSTRC() {
        ostrcWeek = nil
    }

    /// A week whose card closed unanswered is recorded as "no answer" and not
    /// asked again. Only weeks after the person set up the brake.
    func recordUnansweredWeeks() {
        guard let since = profile.consentAt else { return }
        let thisWeek = PainWeek.monday(of: now, calendar: calendar)
        guard let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek),
              now >= PainWeek.closesAt(lastWeek, calendar: calendar),
              PainWeek.asksAt(lastWeek, calendar: calendar) > since,
              painRecord(for: lastWeek) == nil
        else { return }
        context.insert(PainRecord(weekStart: lastWeek, answer: .noAnswer, at: Date()))
        save()
        upload(.pain(.noAnswer, ostrc: nil, week: lastWeek, at: Date(), calendar: calendar), ownAnswer: true)
        track(.painCheckIn(answered: false))
    }
}
