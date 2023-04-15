//
//  SSHShell+async.swift
//  Atomics
//
//  Created by Gaetan Zanella on 10/04/2023.
//

import Foundation

extension SSHShell {

    public typealias AsyncBytes = AsyncThrowingStream<Data, Error>

    public var data: AsyncBytes {
        return AsyncBytes { continuation in
            let readID = addReadListener { continuation.yield($0) }
            let closeID = addCloseListener { error in
                continuation.finish(throwing: error)
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeReadListener(readID)
                self?.removeCloseListener(closeID)
            }
        }
    }

    public func close() async throws {
        return try await withCheckedResultContinuation { completion in
            close(completion: completion)
        }
    }
}
