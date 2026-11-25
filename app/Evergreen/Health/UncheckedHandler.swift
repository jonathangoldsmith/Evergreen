import Foundation

/// HealthKit's completion handler, passed to the main actor. HealthKit allows
/// calling it from any thread, which Swift can't see from its type.
struct UncheckedHandler: @unchecked Sendable {
    let call: () -> Void
}
