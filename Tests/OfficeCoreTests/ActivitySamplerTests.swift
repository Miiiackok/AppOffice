import XCTest
@testable import OfficeCore

private final class FakeUsage: ProcessUsageSource {
    var table: [Int32: ProcessUsage] = [:]
    func usage(pid: Int32) -> ProcessUsage? { table[pid] }
}

final class ActivitySamplerTests: XCTestCase {
    func testFirstSampleHasZeroCPU() {
        let src = FakeUsage()
        src.table[1] = ProcessUsage(cpuNanos: 5_000_000_000, memoryBytes: 100)
        let sampler = ActivitySampler(source: src, family: nil, clock: { 1_000_000_000 })
        XCTAssertEqual(sampler.sample(pids: [1]), [1: ProcessMetrics(cpuPercent: 0, memoryBytes: 100)])
    }

    func testCPUPercentFromDeltas() {
        let src = FakeUsage()
        var now: UInt64 = 0
        let sampler = ActivitySampler(source: src, family: nil, clock: { now })
        src.table[1] = ProcessUsage(cpuNanos: 0, memoryBytes: 1)
        src.table[2] = ProcessUsage(cpuNanos: 0, memoryBytes: 2)
        _ = sampler.sample(pids: [1, 2])
        now = 1_000_000_000
        src.table[1] = ProcessUsage(cpuNanos: 250_000_000, memoryBytes: 1)
        src.table[2] = ProcessUsage(cpuNanos: 1_500_000_000, memoryBytes: 2)
        let m = sampler.sample(pids: [1, 2])
        XCTAssertEqual(m[1]?.cpuPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(m[2]?.cpuPercent ?? -1, 150, accuracy: 0.001)
    }

    func testMissingProcessIsSkippedAndForgotten() {
        let src = FakeUsage()
        var now: UInt64 = 0
        let sampler = ActivitySampler(source: src, family: nil, clock: { now })
        src.table[1] = ProcessUsage(cpuNanos: 0, memoryBytes: 1)
        _ = sampler.sample(pids: [1])
        now = 1_000_000_000
        src.table[1] = nil
        XCTAssertEqual(sampler.sample(pids: [1]), [:])
        // pid 复用：重新出现时按第一次算
        now = 2_000_000_000
        src.table[1] = ProcessUsage(cpuNanos: 9_000_000_000, memoryBytes: 1)
        XCTAssertEqual(sampler.sample(pids: [1])[1]?.cpuPercent, 0)
    }

    func testCPUTimeGoingBackwardsIsZero() {
        let src = FakeUsage()
        var now: UInt64 = 0
        let sampler = ActivitySampler(source: src, family: nil, clock: { now })
        src.table[1] = ProcessUsage(cpuNanos: 5_000, memoryBytes: 1)
        _ = sampler.sample(pids: [1])
        now = 1_000_000_000
        src.table[1] = ProcessUsage(cpuNanos: 1_000, memoryBytes: 1)
        XCTAssertEqual(sampler.sample(pids: [1])[1]?.cpuPercent, 0)
    }

    func testCPUSumsTheWholeProcessFamily() {
        struct Family: ProcessFamilySource {
            var owners: [Int32: Int32]
            func allPIDs() -> [Int32] { Array(owners.keys) }
            func owner(of pid: Int32) -> Int32 { owners[pid] ?? pid }
        }
        let src = FakeUsage()
        var now: UInt64 = 0
        // 1 是 app，2、3 是它的 Helper，9 是别人的进程
        let family = Family(owners: [1: 1, 2: 1, 3: 1, 9: 9])
        let sampler = ActivitySampler(source: src, family: family, clock: { now })
        for pid: Int32 in [1, 2, 3, 9] { src.table[pid] = ProcessUsage(cpuNanos: 0, memoryBytes: UInt64(pid) * 100) }
        _ = sampler.sample(pids: [1])
        now = 1_000_000_000
        src.table[1] = ProcessUsage(cpuNanos: 20_000_000, memoryBytes: 100)
        src.table[2] = ProcessUsage(cpuNanos: 200_000_000, memoryBytes: 200)
        src.table[3] = ProcessUsage(cpuNanos: 80_000_000, memoryBytes: 300)
        src.table[9] = ProcessUsage(cpuNanos: 900_000_000, memoryBytes: 900)
        let m = sampler.sample(pids: [1])
        XCTAssertEqual(m.keys.sorted(), [1])
        XCTAssertEqual(m[1]?.cpuPercent ?? -1, 30, accuracy: 0.001)
        // 内存只算主进程
        XCTAssertEqual(m[1]?.memoryBytes, 100)
    }

    func testSystemFamilyFindsOwnProcess() {
        let family = SystemProcessFamilySource()
        XCTAssertTrue(family.allPIDs().contains(getpid()))
    }

    func testSystemSourceReadsOwnProcess() {
        let usage = SystemProcessUsageSource().usage(pid: getpid())
        XCTAssertNotNil(usage)
        XCTAssertGreaterThan(usage?.cpuNanos ?? 0, 0)
        XCTAssertGreaterThan(usage?.memoryBytes ?? 0, 0)
    }
}
