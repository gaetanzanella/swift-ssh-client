
import Foundation
@testable import SSHClient
import XCTest

class SFTPRequestIDAllocatorTests: XCTestCase {
    func testMonotonicBehavior() {
        var counter = MonotonicRequestIDAllocator(start: 0)
        XCTAssertEqual(counter.allocateRequestID(), 0)
        XCTAssertEqual(counter.allocateRequestID(), 1)
        XCTAssertEqual(counter.allocateRequestID(), 2)
    }

    func testOverflow() {
        var counter = MonotonicRequestIDAllocator(start: .max)
        XCTAssertEqual(counter.allocateRequestID(), .max)
        XCTAssertEqual(counter.allocateRequestID(), 0)
    }
}
