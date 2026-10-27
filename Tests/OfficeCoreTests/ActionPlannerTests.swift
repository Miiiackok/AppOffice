import XCTest
@testable import OfficeCore

final class ActionPlannerTests: XCTestCase {
    private let safari = AppProcess(bundleID: "com.apple.Safari", name: "Safari", pid: 42)
    private let finder = AppProcess(bundleID: "com.apple.finder", name: "Finder", pid: 7)
    private let notesURL = URL(fileURLWithPath: "/System/Applications/Notes.app")

    private func plan(_ action: OfficeAction) -> AppOperation {
        ActionPlanner.plan(action, running: [safari, finder]) { $0 == "com.apple.Notes" ? self.notesURL : nil }
    }

    func testActivateOrLaunchARunningAppSwitchesToIt() {
        XCTAssertEqual(plan(.activate("com.apple.Safari")), .activate(42))
        XCTAssertEqual(plan(.launch("com.apple.Safari")), .activate(42))
    }

    func testActivateOrLaunchAStoppedAppLaunchesIt() {
        XCTAssertEqual(plan(.launch("com.apple.Notes")), .launch(notesURL))
        XCTAssertEqual(plan(.activate("com.apple.Notes")), .launch(notesURL))
        XCTAssertEqual(plan(.launch("com.example.Missing")), .none)
    }

    func testQuit() {
        XCTAssertEqual(plan(.quit("com.apple.Safari")), .quit(42))
        XCTAssertEqual(plan(.quit("com.apple.Notes")), .none)
        XCTAssertEqual(plan(.quit("com.apple.finder")), .none)
    }

    func testReadyDoesNothing() {
        XCTAssertEqual(plan(.ready), .none)
    }
}
