import Foundation

/// A week whose OSTRC questions are waiting, as a sheet item.
struct OSTRCWeek: Identifiable, Hashable {
    let date: Date
    var id: Date { date }
}
