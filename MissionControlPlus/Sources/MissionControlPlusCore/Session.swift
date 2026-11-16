import Foundation

public struct SessionToken: Equatable, Hashable, Sendable {
    public let id: UInt64
    public init(_ id: UInt64) { self.id = id }
}

public final class SessionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    public init() {}

    public var current: SessionToken {
        lock.lock()
        defer { lock.unlock() }
        return SessionToken(value)
    }

    @discardableResult
    public func advance() -> SessionToken {
        lock.lock()
        defer { lock.unlock() }
        value &+= 1
        return SessionToken(value)
    }

    public func isCurrent(_ token: SessionToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token.id == value
    }
}
