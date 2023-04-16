
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
    func openFile(at filePath: SFTPFilePath,
                  flags: SFTPOpenFileFlags,
                  attributes: SFTPFileAttributes = .none) async throws -> SFTPFile {
        try await withCheckedResultContinuation { completion in
            openFile(
                at: filePath,
                flags: flags,
                attributes: attributes,
                completion: completion
            )
        }
    }

    func withFile(at filePath: SFTPFilePath,
                  flags: SFTPOpenFileFlags,
                  attributes: SFTPFileAttributes = .none,
                  _ closure: @escaping (SFTPFile) async -> Void) async throws {
        try await withCheckedResultContinuation { completion in
            withFile(
                at: filePath,
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

    func listDirectory(at path: SFTPFilePath) async throws -> [SFTPPathComponent] {
        try await withCheckedResultContinuation { completion in
            listDirectory(at: path, completion: completion)
        }
    }

    func getAttributes(at filePath: SFTPFilePath) async throws -> SFTPFileAttributes {
        try await withCheckedResultContinuation { completion in
            getAttributes(at: filePath, completion: completion)
        }
    }

    func createDirectory(at path: SFTPFilePath,
                         attributes: SFTPFileAttributes = .none) async throws {
        try await withCheckedResultContinuation { completion in
            createDirectory(at: path, attributes: attributes, completion: completion)
        }
    }

    func moveItem(at current: SFTPFilePath,
                  to destination: SFTPFilePath) async throws {
        try await withCheckedResultContinuation { completion in
            moveItem(at: current, to: destination, completion: completion)
        }
    }

    func removeDirectory(at path: SFTPFilePath) async throws {
        try await withCheckedResultContinuation { completion in
            removeDirectory(at: path, completion: completion)
        }
    }

    func removeFile(at path: SFTPFilePath) async throws {
        try await withCheckedResultContinuation { completion in
            removeFile(at: path, completion: completion)
        }
    }

    func close() async {
        await withCheckedContinuation { continuation in
            close(completion: continuation.resume)
        }
    }
}
