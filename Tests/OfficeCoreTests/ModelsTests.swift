import XCTest
@testable import OfficeCore

final class ModelsTests: XCTestCase {
    func testStatusEncodesProtocolFieldNames() throws {
        let status = EmployeeStatus(id: "com.apple.Safari", state: .focused, cpu: 42, memMB: 812, launchedAt: 1_791_900_000)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as! [String: Any]
        XCTAssertEqual(json["id"] as? String, "com.apple.Safari")
        XCTAssertEqual(json["state"] as? String, "focused")
        XCTAssertEqual(json["cpu"] as? Int, 42)
        XCTAssertEqual(json["memMB"] as? Int, 812)
        XCTAssertEqual(json["launchedAt"] as? Int, 1_791_900_000)
    }

    func testStatusEncodesMissingLaunchAsNull() throws {
        let status = EmployeeStatus(id: "x", state: .off, cpu: 0, memMB: 0, launchedAt: nil)
        let text = String(decoding: try JSONEncoder().encode(status), as: UTF8.self)
        XCTAssertTrue(text.contains("\"launchedAt\":null"), text)
    }
}
