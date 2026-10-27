import XCTest
@testable import OfficeCore

final class MessagesTests: XCTestCase {
    func testParsesActionsFromDictionaryAndString() {
        XCTAssertEqual(OfficeAction.parse(["action": "ready"]), .ready)
        XCTAssertEqual(OfficeAction.parse(["action": "launch", "id": "com.apple.Safari"]), .launch("com.apple.Safari"))
        XCTAssertEqual(OfficeAction.parse(["action": "activate", "id": "y"] as NSDictionary), .activate("y"))
        XCTAssertEqual(OfficeAction.parse("{\"action\":\"quit\",\"id\":\"x\"}"), .quit("x"))
    }

    func testRejectsMalformedActions() {
        XCTAssertNil(OfficeAction.parse(["action": "launch"]))
        XCTAssertNil(OfficeAction.parse(["action": "launch", "id": ""]))
        XCTAssertNil(OfficeAction.parse(["action": "dance", "id": "x"]))
        XCTAssertNil(OfficeAction.parse("not json"))
        XCTAssertNil(OfficeAction.parse(42))
    }

    func testRosterJSON() throws {
        let msg = OutboundMessage.roster([], [RosterItem(id: "a", name: "A", kind: .temp, seat: nil, color: "#112233", iconPNG: "iVBO")])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(msg.json().utf8)) as? [String: Any])
        XCTAssertEqual(obj["type"] as? String, "roster")
        let e = try XCTUnwrap((obj["employees"] as? [[String: Any]])?.first)
        XCTAssertEqual(e["id"] as? String, "a")
        XCTAssertEqual(e["name"] as? String, "A")
        XCTAssertEqual(e["kind"] as? String, "temp")
        XCTAssertTrue(e["room"] is NSNull)
        XCTAssertTrue(e["seat"] is NSNull)
        XCTAssertEqual(e["color"] as? String, "#112233")
        XCTAssertEqual(e["iconPNG"] as? String, "iVBO")
    }

    func testRosterJSONWithRooms() throws {
        let msg = OutboundMessage.roster([RoomInfo(name: "大办公室", kind: .offices), RoomInfo(name: "生活部", kind: .shared)],
                                         [RosterItem(id: "a", name: "A", kind: .staff, room: 1, seat: 2, color: "#112233", iconPNG: "")])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(msg.json().utf8)) as? [String: Any])
        let rooms = try XCTUnwrap(obj["rooms"] as? [[String: Any]])
        XCTAssertEqual(rooms.map { $0["name"] as? String }, ["大办公室", "生活部"])
        XCTAssertEqual(rooms.map { $0["kind"] as? String }, ["offices", "shared"])
        let e = try XCTUnwrap((obj["employees"] as? [[String: Any]])?.first)
        XCTAssertEqual(e["room"] as? Int, 1)
        XCTAssertEqual(e["seat"] as? Int, 2)
    }

    func testStatusAndPausedJSON() {
        let status = OutboundMessage.status(.offline, [EmployeeStatus(id: "a", state: .hung, cpu: 3, memMB: 10, launchedAt: nil)])
        XCTAssertEqual(status.json(),
                       #"{"employees":[{"cpu":3,"id":"a","launchedAt":null,"memMB":10,"state":"hung"}],"network":"offline","type":"status"}"#)
        XCTAssertEqual(OutboundMessage.paused(true).json(), #"{"paused":true,"type":"paused"}"#)
    }
}
