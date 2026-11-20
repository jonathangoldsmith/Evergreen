/// Lets the Done sheet present a completion with `sheet(item:)`.
extension Completion: Identifiable {
    var id: String { planItemId }
}
