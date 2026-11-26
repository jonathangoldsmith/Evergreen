import os

/// The work's answer, or `fallback` once `limit` passes without one. For a
/// HealthKit query that may never return (a simulator whose Health service
/// hangs): the work isn't cancelled, so it must be safe to leave running.
func value<T: Sendable>(within limit: Duration, or fallback: T, _ work: @escaping @Sendable () async -> T) async -> T {
    await withCheckedContinuation { continuation in
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let finish: @Sendable (T) -> Void = { value in
            let first = resumed.withLock { done in
                defer { done = true }
                return !done
            }
            if first { continuation.resume(returning: value) }
        }
        Task { finish(await work()) }
        Task {
            try? await Task.sleep(for: limit)
            finish(fallback)
        }
    }
}
