import Foundation

/// Asks the harness's `POST /workouts/recommend` for the person's next 7 days
/// (harness/INTEGRATION.md, section 6): sessions from their usual week and
/// memory, sized to their training load, sleep and resting heart rate, shoe
/// wear and race taper, each with a reason and citations, plus optional
/// suggestions. Read-only in the app: nothing here touches the plan or the
/// calendar. Uses the same harness URL and secret as `RecommendClient`.
struct PlannerClient: Sendable {
    let baseURL: URL
    let secret: String

    /// The planner answers in about 2 seconds; model-written reasons can take longer.
    static let timeout: TimeInterval = 12

    static func configured(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> PlannerClient? {
        RecommendClient.configured(defaults: defaults, bundle: bundle).map {
            PlannerClient(baseURL: $0.baseURL, secret: $0.secret)
        }
    }

    struct Request: Encodable, Equatable {
        struct Shoes: Encodable, Equatable {
            var boughtOn: String
            var startMiles: Int
        }

        var persona: String
        /// The demo clock with the person's UTC offset.
        var now: String
        var shoes: Shoes?
        /// The new pair's arrival day, once an order is placed.
        var newPairArrives: String?
        var raceDate: String?
        var busy: [Busy]
        /// For a real person: this install's anonymous id and their Apple Health history.
        var user: String? = nil
        var history: HistoryPayload? = nil
    }

    enum Failure: Error, Equatable {
        case unreachable
        case refused(status: Int)
        case unreadable
    }

    /// The request for a person's state. Days are local calendar days, like `RecommendClient`'s.
    static func request(
        persona: String, now: Date, demo: DemoConditions?, newPairArrives: Date?, busy: [Busy], cal: Calendar
    ) -> Request {
        var shoes: Request.Shoes?
        if let boughtOn = demo?.shoesBoughtOn {
            shoes = .init(boughtOn: RecommendClient.day(boughtOn, cal), startMiles: demo?.shoesStartMiles ?? 0)
        }
        return Request(
            persona: persona,
            now: RecommendClient.instant(now, cal),
            shoes: shoes,
            newPairArrives: newPairArrives.map { RecommendClient.day($0, cal) },
            raceDate: demo?.raceDate.map { RecommendClient.day($0, cal) },
            busy: busy
        )
    }

    func week(_ body: Request) async throws(Failure) -> WeekPlan {
        var request = URLRequest(url: baseURL.appending(path: "workouts/recommend"), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Harness-Secret")
        let data: Data
        do {
            request.httpBody = try JSONEncoder.contract.encode(body)
            let (answer, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw Failure.refused(status: http.statusCode)
            }
            data = answer
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .unreachable
        }
        do {
            return try JSONDecoder.contract.decode(WeekPlan.self, from: data)
        } catch {
            throw .unreadable
        }
    }
}
