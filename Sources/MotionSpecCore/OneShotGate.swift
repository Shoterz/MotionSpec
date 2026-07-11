public struct OneShotGate: Equatable, Sendable {
    private var hasAccepted = false

    public init() { }

    public mutating func accept() -> Bool {
        guard !hasAccepted else {
            return false
        }

        hasAccepted = true
        return true
    }
}
