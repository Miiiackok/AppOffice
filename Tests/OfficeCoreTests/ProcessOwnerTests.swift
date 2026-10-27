import XCTest
@testable import OfficeCore

final class ProcessOwnerTests: XCTestCase {
    func testOwnerOfSelfIsPositive() {
        XCTAssertGreaterThan(ProcessOwner.owner(of: getpid()), 0)
    }

    func testChildMapsAwayFromItself() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        try child.run()
        defer { child.terminate(); child.waitUntilExit() }
        XCTAssertNotEqual(ProcessOwner.owner(of: child.processIdentifier), child.processIdentifier)
    }
}
