import XCTest
@testable import OfficeCore

final class StatusDifferTests: XCTestCase {
    private func s(_ id: String, _ state: EmployeeState, cpu: Int = 0) -> EmployeeStatus {
        EmployeeStatus(id: id, state: state, cpu: cpu, memMB: 0, launchedAt: nil)
    }

    func testFirstCallReturnsEverything() {
        var d = StatusDiffer()
        XCTAssertEqual(d.changes([s("a", .off), s("b", .idle)]), [s("a", .off), s("b", .idle)])
    }

    func testOnlyChangedAfterwards() {
        var d = StatusDiffer()
        _ = d.changes([s("a", .off), s("b", .idle)])
        XCTAssertEqual(d.changes([s("a", .off), s("b", .idle, cpu: 3)]), [s("b", .idle, cpu: 3)])
        XCTAssertEqual(d.changes([s("a", .off), s("b", .idle, cpu: 3)]), [])
    }

    func testResetSendsEverythingAgain() {
        var d = StatusDiffer()
        _ = d.changes([s("a", .off)])
        d.reset()
        XCTAssertEqual(d.changes([s("a", .off)]), [s("a", .off)])
    }
}
