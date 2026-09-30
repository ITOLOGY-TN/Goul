import Foundation

/// Identifies the sole active utterance, rejecting results from canceled tasks.
public struct SessionGate: Sendable {
    private var active: UUID?
    public init() {}
    public mutating func begin() -> UUID {
        let id = UUID()
        active = id
        return id
    }
    public func accepts(_ id: UUID) -> Bool { active == id }
    public mutating func cancel() { active = nil }
    public mutating func complete(_ id: UUID) {
        if active == id { active = nil }
    }
}
public enum ClipboardOwnership {
    public static func canRestore(written: Int, current: Int) -> Bool { written == current }
}
