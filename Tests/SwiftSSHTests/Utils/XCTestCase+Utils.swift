
import Foundation
import XCTest

extension XCTestCase {

    func wait(timeout: TimeInterval) {
        _ = XCTWaiter.wait(for: [expectation(description: "Wait for n seconds")], timeout: timeout)

    }
}

extension Result {

    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    var isFailure: Bool {
        switch self {
        case .success:
            return false
        case .failure:
            return true
        }
    }
}
