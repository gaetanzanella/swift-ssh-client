
import Foundation

public extension SFTPFile {
    func readAttributes() async throws -> SFTPFileAttributes {
        try await withCheckedResultContinuation { completion in
            readAttributes(completion: completion)
        }
    }

    func read(from offset: UInt64 = 0,
              length: UInt32 = .max) async throws -> Data {
        try await withCheckedResultContinuation { completion in
            read(from: offset, length: length, completion: completion)
        }
    }

    func write(_ data: Data,
               at offset: UInt64 = 0) async throws {
        try await withCheckedResultContinuation { completion in
            write(data, at: offset, completion: completion)
        }
    }

    func close() async throws {
        try await withCheckedResultContinuation { completion in
            close(completion: completion)
        }
    }
}

public extension SFTPClient {
    func openFile(filePath: String,
                  flags: SFTPOpenFileFlags,
                  attributes: SFTPFileAttributes = .none) async throws -> SFTPFile {
        try await withCheckedResultContinuation { completion in
            openFile(
                filePath: filePath,
                flags: flags,
                attributes: attributes,
                completion: completion
            )
        }
    }

    func withFile(filePath: String,
                  flags: SFTPOpenFileFlags,
                  attributes: SFTPFileAttributes = .none,
                  _ closure: @escaping (SFTPFile) async -> Void) async throws {
        try await withCheckedResultContinuation { completion in
            withFile(
                filePath: filePath,
                flags: flags,
                attributes: attributes, { file, close in
                    Task {
                        await closure(file)
                        close()
                    }
                },
                completion: completion
            )
        }
    }

    func listDirectory(atPath path: String) async throws -> [SFTPPathComponent] {
        try await withCheckedResultContinuation { completion in
            listDirectory(atPath: path, completion: completion)
        }
    }

    func getAttributes(at filePath: String) async throws -> SFTPFileAttributes {
        try await withCheckedResultContinuation { completion in
            getAttributes(at: filePath, completion: completion)
        }
    }

    func createDirectory(atPath path: String,
                         attributes: SFTPFileAttributes = .none) async throws {
        try await withCheckedResultContinuation { completion in
            createDirectory(atPath: path, attributes: attributes, completion: completion)
        }
    }

    func moveItem(atPath current: String,
                  toPath destination: String) async throws {
        try await withCheckedResultContinuation { completion in
            moveItem(atPath: current, toPath: destination, completion: completion)
        }
    }

    func removeDirectory(atPath path: String) async throws {
        try await withCheckedResultContinuation { completion in
            removeDirectory(atPath: path, completion: completion)
        }
    }

    func removeFile(atPath path: String) async throws {
        try await withCheckedResultContinuation { completion in
            removeFile(atPath: path, completion: completion)
        }
    }

    func close() async {
        await withCheckedContinuation { continuation in
            close(completion: continuation.resume)
        }
    }
}
