//
//  SSHShell+async.swift
//  Atomics
//
//  Created by Gaetan Zanella on 10/04/2023.
//

import Foundation

public extension SSHShell {
    typealias AsyncBytes = AsyncThrowingStream<Data, Error>

    var data: AsyncBytes {
        AsyncBytes { continuation in
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

    func close() async throws {
        try await withCheckedResultContinuation { completion in
            close(completion: completion)
        }
    }
}
