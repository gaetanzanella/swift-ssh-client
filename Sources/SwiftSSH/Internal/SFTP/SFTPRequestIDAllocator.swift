
import Foundation

protocol SFTPRequestIDAllocator {
    mutating func allocateRequestID() -> SFTPRequestID
}

struct MonotonicRequestIDAllocator: SFTPRequestIDAllocator {

    private var i: SFTPRequestID

    init(start: SFTPRequestID) {
        self.i = start
    }

    mutating func allocateRequestID() -> SFTPRequestID {
        defer { i = i == .max ? 0 : i + 1 }
        return i
    }
}
