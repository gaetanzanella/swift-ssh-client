
import Foundation

extension SFTPFile {

    public func readAttributes() async throws -> SFTPFileAttributes {
        return try await withCheckedResultContinuation { completion in
            readAttributes(completion: completion)
        }
    }

    public func read(from offset: UInt64 = 0,
                     length: UInt32 = .max) async throws -> Data {
        return try await withCheckedResultContinuation { completion in
            read(from: offset, length: length, completion: completion)
        }
    }

    public func write(_ data: Data,
                      at offset: UInt64 = 0) async throws {
        return try await withCheckedResultContinuation { completion in
            write(data, at: offset, completion: completion)
        }
    }

    public func close() async throws {
        return try await withCheckedResultContinuation { completion in
            close(completion: completion)
        }
    }
}

extension SFTPClient {

    public func openFile(filePath: String,
                         flags: SFTPOpenFileFlags,
                         attributes: SFTPFileAttributes = .none) async throws -> SFTPFile {
        return try await withCheckedResultContinuation { completion in
            openFile(
                filePath: filePath,
                flags: flags,
                attributes: attributes,
                completion: completion
            )
        }
    }

    public func withFile(filePath: String,
                         flags: SFTPOpenFileFlags,
                         attributes: SFTPFileAttributes = .none,
                         _ closure: @escaping (SFTPFile) async -> Void) async throws {
        return try await withCheckedResultContinuation { completion in
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

    public func listDirectory(atPath path: String) async throws -> [SFTPPathComponent] {
        return try await withCheckedResultContinuation { completion in
            listDirectory(atPath: path, completion: completion)
        }
    }

    public func getAttributes(at filePath: String) async throws -> SFTPFileAttributes {
        return try await withCheckedResultContinuation { completion in
            getAttributes(at: filePath, completion: completion)
        }
    }

    public func createDirectory(atPath path: String,
                                attributes: SFTPFileAttributes = .none) async throws {
        return try await withCheckedResultContinuation { completion in
            createDirectory(atPath: path, attributes: attributes, completion: completion)
        }
    }

    public func moveItem(atPath current: String,
                         toPath destination: String) async throws {
        return try await withCheckedResultContinuation { completion in
            moveItem(atPath: current, toPath: destination, completion: completion)
        }
    }

    public func removeDirectory(atPath path: String) async throws {
        return try await withCheckedResultContinuation { completion in
            removeDirectory(atPath: path, completion: completion)
        }
    }

    public func removeFile(atPath path: String) async throws {
        return try await withCheckedResultContinuation { completion in
            removeFile(atPath: path, completion: completion)
        }
    }

    public func close() async {
        return await withCheckedContinuation { continuation in
            close(completion: continuation.resume)
        }
    }
}
