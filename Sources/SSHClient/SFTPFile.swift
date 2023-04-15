import Foundation
import NIO

public final class SFTPFile: @unchecked Sendable {

    private var isActive: Bool

    private let handle: SFTPFileHandle
    private let path: String
    private let channel: SFTPChannel
    private let updateQueue: DispatchQueue

    // MARK: - Life Cycle

    init(channel: SFTPChannel,
         path: String,
         handle: SFTPFileHandle,
         updateQueue: DispatchQueue) {
        isActive = true
        self.handle = handle
        self.channel = channel
        self.path = path
        self.updateQueue = updateQueue
    }

    deinit {
        assert(!self.isActive, "SFTPFile deallocated without being closed first")
    }

    // MARK: - Public

    public func readAttributes(completion: @escaping (Result<SFTPFileAttributes, Error>) -> Void) {
        channel.stat(path: path)
            .map { $0.attributes }
            .whenComplete(on: updateQueue, completion)
    }

    public func read(from offset: UInt64 = 0,
                     length: UInt32 = .max,
                     completion: @escaping (Result<Data, Error>) -> Void) {
        let message = SFTPMessage.ReadFile.Payload(
            handle: handle,
            offset: offset,
            length: length
        )
        channel.readFile(message)
            .map { (response: SFTPMessage.ReadFile.Response) -> Data in
                switch response {
                case .fileData(let data):
                    var d = data.data
                    return d.readData(length: d.readableBytes) ?? Data()
                case .status:
                    return Data()
                }
            }
            .whenComplete(on: updateQueue, completion)
    }

    public func write(_ data: Data,
                      at offset: UInt64 = 0,
                      completion: @escaping (Result<Void, Error>) -> Void) {
        let data = ByteBuffer(data: data)
        let sliceLength = 32000
        let promise = writeSlice(
            data: data,
            sliceLength: sliceLength,
            offset: offset
        )
        if let promise = promise {
            return promise
                .whenComplete(on: updateQueue, completion)
        } else {
            updateQueue.async {
                completion(.failure(SFTPError.invalidResponse))
            }
        }
    }

    public func close(completion: @escaping (Result<Void, Error>) -> Void) {
        channel.closeFile(handle)
            .mapAsVoid()
            .whenComplete { result in
                self.isActive = false
                self.updateQueue.async {
                    completion(result)
                }
            }
    }

    // MARK: - Private

    private func writeSlice(data: ByteBuffer,
                            sliceLength: Int,
                            offset: UInt64) -> EventLoopFuture<Void>? {
        var data = data
        guard data.readableBytes > 0,
              let slice = data.readSlice(length: Swift.min(sliceLength, data.readableBytes))
        else {
            return nil
        }
        let message = SFTPMessage.WriteFile.Payload(
            handle: handle,
            offset: offset + UInt64(data.readerIndex) - UInt64(slice.readableBytes),
            data: slice
        )
        let future = channel.writeFile(message)
        return future
            .flatMap { _ in
                if let promise = self.writeSlice(
                    data: data,
                    sliceLength: sliceLength,
                    offset: offset
                ) {
                    return promise
                }
                return future.map { _ in }
            }
    }
}
