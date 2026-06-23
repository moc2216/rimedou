enum TestExpect {
    static func isTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fatalError(message)
        }
    }

    static func equal<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            fatalError("\(message): actual=\(actual), expected=\(expected)")
        }
    }

    static func isNil<T>(_ value: T?, _ message: String) {
        if value != nil {
            fatalError(message)
        }
    }
}
