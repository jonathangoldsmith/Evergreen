import Foundation

// The shopping beat (docs/designs/trackerplusplus-shopping-beat.md): one purchase
// engine, ask-first shoes for Jordan. Each change in a purchase's life is a new
// action with its own stable id, because the phone ignores ids it already has;
// the UI folds them by `purchaseId`. Rules live only here on demo day (eng
// review D1); the harness serves Senso evidence through `POST /evidence`.

extension StandInAgent {
    /// Workouts carry no distance, so mileage uses a fixed 9 min/mi pace.
    static let minutesPerMile = 9.0
    /// Replace when the pair is this close to ~400 miles…
    static let replaceAtMiles = 375
    /// …and a race is this near.
    static let raceWindowDays = 14
    /// A new pair must arrive this long before the race to break it in.
    static let breakInDays = 3

    func purchaseActions(
        _ s: TickSnapshot, known: Set<String>, done: Set<String>, cal: Calendar
    ) async -> [AgentAction] {
        let shoes = await shoesActions(s, known: known, cal: cal) ?? []
        let pass = await dayPassActions(s, known: known, done: done, cal: cal)
        return shoes + pass
    }

    // MARK: Day pass (auto-buy branch)

    static let gym = "Demo Gym"
    static let dayPassCents = 1500
    static let outdoorTypes: Set<String> = ["Walking", "Running", "Cycling"]
    /// Rain this close before a workout still spoils it.
    static let rainLead: TimeInterval = 30 * 60
    /// The pass cancels free until this long before the workout.
    static let freeCancel: TimeInterval = 60 * 60

    /// Rain on an outdoor workout: buy a day pass under the person's rule and
    /// move the workout indoors; cancel it if the forecast clears or the person
    /// undoes it before the free-cancel deadline; close the trail on arrival.
    private func dayPassActions(
        _ s: TickSnapshot, known: Set<String>, done: Set<String>, cal: Calendar
    ) async -> [AgentAction] {
        guard let rainAt = s.demo?.rainAt else { return [] }
        let undone = Set(s.undoneActionIds)
        var actions: [AgentAction] = []

        for item in s.plan.sorted(by: { $0.slot.start < $1.slot.start })
        where Self.outdoorTypes.contains(item.slot.activityType) && !done.contains(item.id)
            && rainAt >= item.slot.start.addingTimeInterval(-Self.rainLead) && rainAt <= item.slot.end {
            // Before the person has verified their identity the agent asks
            // first. The ask is its own purchase id, so a "Not now" on it is
            // never read as an undone auto-buy that needs a refund.
            let epoch = Int(rainAt.timeIntervalSince1970)
            let askBase = "pass-ask-\(item.id)-\(epoch)"
            let asks = known.contains("purchase-\(askBase)") || !s.identityVerified
            let id = asks ? askBase : "pass-\(item.id)-\(epoch)"
            let buyId = "purchase-\(id)"
            let boughtId = asks ? "\(buyId)-bought" : buyId
            let cancelId = "\(buyId)-cancel"
            let outcomeId = "\(buyId)-outcome"
            let askMandate = s.mandate.filter { $0.category != .dayPass }

            if asks {
                if !known.contains(buyId) {
                    guard !(s.demo?.forecastClear ?? false), s.now < item.slot.start,
                          let ask = await dayPass(id: id, item: item, rainAt: rainAt, mandate: askMandate)
                    else { continue }
                    actions.append(AgentAction(
                        id: buyId, kind: .purchase, title: "Found a gym day pass", planItemId: item.id,
                        reason: "Rain at \(rainAt.clock) would wash out your \(Activity.noun(item.slot.activityType)). I buy passes on my own only after you've verified your identity.",
                        createdAt: s.now, purchaseId: id, purchase: ask
                    ))
                    continue
                }
                // "Not now" ends it.
                if undone.contains(buyId) { continue }
                // "Order it" buys the pass and moves the workout indoors.
                if !known.contains(boughtId) {
                    guard s.approvedPurchaseIds.contains(id), !(s.demo?.forecastClear ?? false), s.now < item.slot.start,
                          var pass = s.actions.first(where: { $0.id == buyId })?.purchase
                    else { continue }
                    pass.status = .bought
                    var after = item.slot
                    after.place = Self.gym
                    actions.append(AgentAction(
                        id: boughtId, kind: .purchase, title: "Bought a gym day pass", planItemId: item.id,
                        before: item.slot, after: after,
                        reason: "You said yes. Demo Gym, no charge; your \(Activity.noun(item.slot.activityType)) moves indoors.",
                        createdAt: s.now, purchaseId: id, purchase: pass
                    ))
                    continue
                }
                // Bought: cancelling and the arrival work as for an auto-buy, below.
            }

            // The snapshot only carries actions still in effect, so an undone
            // pass is rebuilt from the plan item (back at its original slot).
            let bought = s.actions.first { $0.id == boughtId }
            let personUndid = undone.contains(boughtId)
            guard bought != nil || personUndid else {
                // Buy once, before the workout, while rain is still forecast.
                guard !known.contains(buyId), !(s.demo?.forecastClear ?? false), s.now < item.slot.start,
                      let purchase = await dayPass(id: id, item: item, rainAt: rainAt, mandate: s.mandate)
                else { continue }
                var after = item.slot
                after.place = Self.gym
                actions.append(AgentAction(
                    id: buyId, kind: .purchase, title: "Bought a gym day pass", planItemId: item.id,
                    before: item.slot, after: after,
                    reason: "Rain at \(rainAt.clock) would wash out your \(Activity.noun(item.slot.activityType)), and Demo Gym is 0.4 mi from work.",
                    createdAt: s.now, purchaseId: id, purchase: purchase
                ))
                continue
            }
            guard !known.contains(cancelId) else { continue }
            var rebuilt = bought?.purchase
            if rebuilt == nil {
                rebuilt = await dayPass(id: id, item: item, rainAt: rainAt, mandate: asks ? askMandate : s.mandate, live: false)
            }
            guard let pass = rebuilt else { continue }
            let original = bought?.before ?? item.slot
            var inGym = bought?.after ?? item.slot
            inGym.place = Self.gym
            let cancelBy = pass.cancelBy ?? item.slot.start

            // The person's Undo before the deadline, or a clear forecast: the
            // agent cancels its own purchase and the workout goes back outside.
            let cleared = s.demo?.forecastClear == true && !personUndid
            if (personUndid || cleared), s.now < cancelBy {
                var cancelled = pass
                cancelled.status = .cancelled
                cancelled.outcome = "\(ActionCopy.money(pass.amountCents)) refunded"
                if cleared {
                    cancelled.noticed = "The forecast cleared for \(original.start.clock), so the pass isn't needed."
                }
                actions.append(AgentAction(
                    id: cancelId, kind: .cancelPurchase,
                    title: "Cancelled the day pass", planItemId: item.id, before: inGym, after: original,
                    reason: personUndid
                        ? "You cancelled it. \(ActionCopy.money(pass.amountCents)) refunded."
                        : "Forecast cleared for \(original.start.clock). \(ActionCopy.money(pass.amountCents)) refunded; your \(Activity.noun(original.activityType)) is back outside.",
                    createdAt: s.now, purchaseId: id, purchase: cancelled
                ))
                continue
            }
            guard !personUndid, !known.contains(outcomeId) else { continue }

            // Arriving at the gym during the workout window closes the trail.
            if let visit = s.visits.first(where: {
                $0.place == Self.gym && $0.at <= s.now
                    && $0.at >= item.slot.start.addingTimeInterval(-Self.rainLead) && $0.at <= item.slot.end
            }) {
                var used = pass
                used.outcome = "Arrived \(Self.gym) \(visit.at.clock) · pass used"
                actions.append(AgentAction(
                    id: outcomeId, kind: .purchaseOutcome, title: "Pass used", planItemId: item.id,
                    reason: "You made it to \(Self.gym), so the pass did its job.",
                    createdAt: s.now, purchaseId: id, purchase: used
                ))
            }
        }
        return actions
    }

    private func dayPass(
        id: String, item: PlanItem, rainAt: Date, mandate: [Mandate], live useLive: Bool = true
    ) async -> Purchase? {
        // A day pass under the day-pass line is bought without asking.
        let rule = mandate.first { $0.category == .dayPass && Self.dayPassCents <= $0.maxAutoCents }
            ?? mandate.first { $0.category == .any }
        guard let rule else { return nil }
        let auto = rule.category == .dayPass
        let noun = Activity.noun(item.slot.activityType)
        let live = !useLive ? nil : await evidence?.passages(kind: "dayPass", query: "Demo Gym day pass price and cancellation; rain at \(rainAt.clock)")
        return Purchase(
            id: id, item: "\(Self.gym) day pass", merchant: "Demo Gym (no charge)", amountCents: Self.dayPassCents,
            status: auto ? .bought : .awaitingApproval,
            rule: Purchase.Rule(id: rule.id, text: rule.text),
            noticed: "Rain is forecast at \(rainAt.clock), right when your \(item.slot.start.clock) \(noun) starts.",
            evidence: live ?? [
                Purchase.Evidence(source: "Demo forecast", passage: "80% chance of rain at \(rainAt.clock)."),
                Purchase.Evidence(source: "Demo Gym day-pass policy",
                                  passage: "Day pass $15. Free cancellation until 60 minutes before your visit."),
                Purchase.Evidence(source: "Demo Gym listing", passage: "0.4 mi from work. Treadmills and a walking track; open until 10 PM."),
            ],
            evidenceLive: live != nil,
            options: [
                Purchase.Option(name: "\(Self.gym) day pass", amountCents: Self.dayPassCents),
                Purchase.Option(name: "\(noun.capitalized) outside anyway", amountCents: 0,
                                lostBecause: "80% rain at \(rainAt.clock); a washed-out \(noun) is a second miss"),
                Purchase.Option(name: "Move it to tomorrow", amountCents: 0,
                                lostBecause: "Gives up today's comeback and its 2× points"),
            ],
            cancelBy: item.slot.start.addingTimeInterval(-Self.freeCancel)
        )
    }

    // MARK: Shoes (ask-first branch)

    /// A listing in the demo store, relative to the story day.
    private struct Listing {
        var name: String
        var amountCents: Int
        var arrivesInDays: Int
        var wideToeBox: Bool
    }

    private static let listings = [
        Listing(name: "Pacer 9", amountCents: 13800, arrivesInDays: 3, wideToeBox: true),
        Listing(name: "Glide Trainer", amountCents: 12500, arrivesInDays: 7, wideToeBox: true),
        Listing(name: "Tempo Lite", amountCents: 9600, arrivesInDays: 4, wideToeBox: false),
    ]

    /// Miles on the current pair, rounded to the nearest mile.
    static func shoeMiles(_ s: TickSnapshot) -> Int? {
        guard let demo = s.demo, let boughtOn = demo.shoesBoughtOn, let start = demo.shoesStartMiles else { return nil }
        let minutes = s.workouts
            .filter { $0.activityType == "Running" && $0.start >= boughtOn && $0.start <= s.now }
            .reduce(0) { $0 + $1.minutes }
        return Int((Double(start) + minutes / minutesPerMile).rounded())
    }

    private func shoesActions(_ s: TickSnapshot, known: Set<String>, cal: Calendar) async -> [AgentAction]? {
        guard let demo = s.demo, let boughtOn = demo.shoesBoughtOn, let raceDate = demo.raceDate,
              let miles = Self.shoeMiles(s), miles >= Self.replaceAtMiles else { return nil }
        let day = cal.startOfDay(for: s.now)
        let race = cal.startOfDay(for: raceDate)
        guard let daysToRace = cal.dateComponents([.day], from: day, to: race).day,
              (0...Self.raceWindowDays).contains(daysToRace) else { return nil }

        let id = "shoes-\(boughtOn.formatted(.iso8601.year().month().day()))"
        let askId = "purchase-\(id)"
        let boughtId = "\(askId)-bought"
        let cancelId = "\(askId)-cancel"
        let undone = Set(s.undoneActionIds)
        var actions: [AgentAction] = []

        // Ask once. "Not now" undoes the ask, and an undone id is known, so it never asks again.
        let asked: Purchase
        if let existing = s.actions.first(where: { $0.id == askId })?.purchase {
            asked = existing
        } else if known.contains(askId) {
            return [] // declined with "Not now"
        } else {
            guard let purchase = await shoesPurchase(
                id: id, miles: miles, daysToRace: daysToRace, day: day, race: race, mandate: s.mandate, cal: cal
            ) else {
                return []
            }
            actions.append(AgentAction(
                id: askId, kind: .purchase, title: "Picked new running shoes",
                reason: "Matches your wide-toe-box note and arrives before race day. Free returns for 30 days.",
                createdAt: s.now, purchaseId: id, purchase: purchase
            ))
            return actions
        }
        guard !undone.contains(askId) else { return [] }

        // "Order it" → bought, then two break-in runs between arrival and race day.
        if s.approvedPurchaseIds.contains(id), !known.contains(boughtId) {
            var bought = asked
            bought.status = .bought
            let arrives = asked.options.first?.arrives ?? day
            actions.append(AgentAction(
                id: boughtId, kind: .purchase, title: "Ordered new running shoes",
                reason: "You said yes. Demo store, no charge. It arrives \(arrives.formatted(.dateTime.weekday(.wide))).",
                createdAt: s.now, purchaseId: id, purchase: bought
            ))
            for (index, slot) in Self.breakInRuns(arrives: arrives, race: race, cal: cal).enumerated() {
                let runId = "breakin-\(id)-\(index + 1)"
                guard !known.contains(runId) else { continue }
                actions.append(AgentAction(
                    id: runId, kind: .addWorkout, title: "Added a break-in run", planItemId: runId,
                    after: slot,
                    reason: "New shoes need a couple of easy runs before race day.",
                    points: Self.basePoints, createdAt: s.now, purchaseId: id, purchase: bought
                ))
            }
        }

        // "Cancel order" undoes the bought action.
        if undone.contains(boughtId), !known.contains(cancelId) {
            var cancelled = asked
            cancelled.status = .cancelled
            cancelled.outcome = "Order cancelled, no charge."
            actions.append(AgentAction(
                id: cancelId, kind: .cancelPurchase, title: "Cancelled the order",
                reason: "You cancelled it. No charge, and the break-in runs are off your plan.",
                createdAt: s.now, purchaseId: id, purchase: cancelled
            ))
        }
        return actions
    }

    /// Keeps pairs that fit the fit notes and arrive in time, then picks the cheapest.
    private func shoesPurchase(
        id: String, miles: Int, daysToRace: Int, day: Date, race: Date, mandate: [Mandate], cal: Calendar
    ) async -> Purchase? {
        let latestArrival = cal.date(byAdding: .day, value: -Self.breakInDays, to: race) ?? race
        var kept: [Purchase.Option] = []
        var lost: [Purchase.Option] = []
        for listing in Self.listings {
            let arrives = cal.date(byAdding: .day, value: listing.arrivesInDays, to: day)!
            var option = Purchase.Option(name: listing.name, amountCents: listing.amountCents, arrives: arrives)
            if !listing.wideToeBox {
                option.lostBecause = "Narrow toe box (your fit notes say wide)"
            } else if arrives > latestArrival {
                let early = cal.dateComponents([.day], from: arrives, to: race).day ?? 0
                option.lostBecause = "Arrives \(arrives.formatted(.dateTime.weekday(.wide))), \(early) days before the race: no time to break in"
            }
            if option.lostBecause == nil { kept.append(option) } else { lost.append(option) }
        }
        guard let chosen = kept.min(by: { $0.amountCents < $1.amountCents }) else { return nil }
        let others = kept.filter { $0.name != chosen.name }.map {
            var option = $0
            option.lostBecause = "Costs more than \(chosen.name)"
            return option
        }

        let query = "running shoes replacement mileage, wide toe box, arrives by \(race.formatted(date: .abbreviated, time: .omitted))"
        let live = await evidence?.passages(kind: "shoes", query: query)
        // Shoes aren't a day pass, so the catch-all line decides: over its limit, ask first.
        let rule = mandate.first { $0.category == .any }
            ?? Mandate(id: "ask-first", text: "Ask me before buying anything.", category: .any, maxAutoCents: 0)
        let auto = chosen.amountCents <= rule.maxAutoCents
        return Purchase(
            id: id, item: chosen.name, merchant: "Demo store, no charge", amountCents: chosen.amountCents,
            status: auto ? .bought : .awaitingApproval,
            rule: Purchase.Rule(id: rule.id, text: rule.text),
            noticed: "Your shoes hit \(miles) miles. Race day is in \(daysToRace) days.",
            evidence: live ?? Self.cachedShoeEvidence(chosen),
            evidenceLive: live != nil,
            options: [chosen] + others + lost
        )
    }

    /// One easy 30-minute run the evening after the pair arrives, and a
    /// 25-minute one in the morning three days before the race.
    static func breakInRuns(arrives: Date, race: Date, cal: Calendar) -> [Slot] {
        let dayAfter = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: arrives))!
        let late = cal.date(byAdding: .day, value: -Self.breakInDays, to: race)!
        let first = cal.date(bySettingHour: 18, minute: 0, second: 0, of: dayAfter)!
        let second = cal.date(bySettingHour: 7, minute: 0, second: 0, of: late)!
        return [
            Slot(start: first, end: first.addingTimeInterval(30 * 60), activityType: "Running"),
            Slot(start: second, end: second.addingTimeInterval(25 * 60), activityType: "Running"),
        ]
    }

    /// The Senso passages bundled for the offline stage, marked "cached".
    static func cachedShoeEvidence(_ chosen: Purchase.Option) -> [Purchase.Evidence] {
        let arrives = chosen.arrives.map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "soon"
        return [
            Purchase.Evidence(source: "Running shoe care guide",
                              passage: "Replace road running shoes every 300 to 500 miles, sooner if the midsole feels flat."),
            Purchase.Evidence(source: "Jordan's fit notes", passage: "Wide toe box, no carbon plate."),
            Purchase.Evidence(source: "\(chosen.name) listing",
                              passage: "Ships next day; arrives \(arrives). Free returns for 30 days."),
        ]
    }
}
