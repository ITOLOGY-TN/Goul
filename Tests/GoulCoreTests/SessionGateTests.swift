import Foundation
import Testing
@testable import GoulCore

struct SessionGateTests {
    @Test func canceledWorkCannotFinishANewerSession() {
        var gate = SessionGate()
        let old = gate.begin()
        gate.cancel()
        let current = gate.begin()
        #expect(!gate.accepts(old))
        #expect(gate.accepts(current))
        gate.complete(old)
        #expect(gate.accepts(current))
        gate.complete(current)
        #expect(!gate.accepts(current))
    }
    @Test func cancellationInvalidatesPendingResult() {
        var gate = SessionGate()
        let id = gate.begin()
        gate.cancel()
        #expect(!gate.accepts(id))
    }
    @Test func clipboardRestorationPreservesNewerCopies() {
        #expect(ClipboardOwnership.canRestore(written: 12, current: 12))
        #expect(!ClipboardOwnership.canRestore(written: 12, current: 13))
    }
}
