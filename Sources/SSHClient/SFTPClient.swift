import Foundation
import NIO
import NIOCore

public enum SFTPClientError: Error {
    case requireConnection
    case unknown
}

public final class SFTPClient: SSHSession {
    enum State: Equatable {
        case idle
        case ready
        case closed
        case failed(SFTPClientError)
    }

    private let updateQueue: DispatchQueue
    private var sftpChannel: SFTPChannel

    // For testing purpose.
    // We expose a simple `closeHandler` instead of the state as the starting is
    // entirely managed by `SSHConnection` and a `SFTPClient` can not restart.
    var state: State {
        sftpChannel.state
    }

    var stateUpdateHandler: ((State) -> Void)?

    // MARK: - Life Cycle

    init(sftpChannel: SFTPChannel,
         updateQueue: DispatchQueue) {
        self.sftpChannel = sftpChannel
        self.updateQueue = updateQueue
        setupIOChannel()
    }

    // MARK: - SSHSession

    func start(in context: SSHSessionContext) {
        sftpChannel.start(in: context)
    }

    // MARK: - Public

    public var closeHandler: ((SFTPClientError?) -> Void)?

    public func listDirectory(atPath path: String,
                              completion: @escaping ((Result<[SFTPPathComponent], Error>) -> Void)) {
        let newPath = recursivelyExecute(
            { path in
                self.sftpChannel.realpath(path: path).map {
                    $0.components.first?.filename ?? ""
                }
            },
            merge: { new, current in
                (new, new != current)
            },
            response: path
        )
        newPath.flatMap { path in
            self.sftpChannel.openDir(path: path)
        }
        .flatMap { (handle: SFTPMessage.Handle) in
            self.recursivelyExecute(
                { (_: [SFTPPathComponent]) in
                    self.sftpChannel.readDir(handle.handle)
                },
                merge: { (response: SFTPMessage.ReadDir.Response, current: [SFTPPathComponent]) in
                    switch response {
                    case .name(let name):
                        return (current + name.components, true)
                    case .status:
                        return (current, false)
                    }
                },
                response: []
            )
        }
        .whenComplete(on: updateQueue, completion)
    }

    public func getAttributes(at filePath: String,
                              completion: @escaping ((Result<SFTPFileAttributes, Error>) -> Void)) {
        sftpChannel.stat(path: filePath)
            .map { $0.attributes }
            .whenComplete(on: updateQueue, completion)
    }

    public func openFile(filePath: String,
                         flags: SFTPOpenFileFlags,
                         attributes: SFTPFileAttributes = .none,
                         updateQueue: DispatchQueue = .main,
                         completion: @escaping (Result<SFTPFile, Error>) -> Void) {
        let message = SFTPMessage.OpenFile.Payload(
            filePath: filePath,
            pFlags: flags,
            attributes: attributes
        )
        return sftpChannel.openFile(message)
            .map { handle in
                SFTPFile(
                    channel: self.sftpChannel,
                    path: filePath,
                    handle: handle.handle,
                    updateQueue: updateQueue
                )
            }
            .whenComplete(on: updateQueue, completion)
    }

    public func withFile(filePath: String,
                         flags: SFTPOpenFileFlags,
                         attributes: SFTPFileAttributes = .none,
                         _ closure: @escaping (SFTPFile, @escaping () -> Void) -> Void,
                         completion: @escaping (Result<Void, Error>) -> Void) {
        openFile(
            filePath: filePath,
            flags: flags,
            attributes: attributes,
            updateQueue: .global(qos: .utility)
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let file):
                closure(file) {
                    file.close(completion: completion)
                }
            }
        }
    }

    public func createDirectory(atPath path: String,
                                attributes: SFTPFileAttributes = .none,
                                completion: @escaping ((Result<Void, Error>) -> Void)) {
        let message = SFTPMessage.MkDir.Payload(
            filePath: path,
            attributes: attributes
        )
        return sftpChannel.mkdir(message)
            .mapAsVoid()
            .whenComplete(on: updateQueue, completion)
    }

    public func moveItem(atPath current: String,
                         toPath destination: String,
                         completion: @escaping ((Result<Void, Error>) -> Void)) {
        let message = SFTPMessage.Rename.Payload(oldPath: current, newPath: destination)
        return sftpChannel.rename(message)
            .mapAsVoid()
            .whenComplete(on: updateQueue, completion)
    }

    public func removeDirectory(atPath path: String,
                                completion: @escaping ((Result<Void, Error>) -> Void)) {
        sftpChannel.rmdir(path: path)
            .mapAsVoid()
            .whenComplete(on: updateQueue, completion)
    }

    public func removeFile(atPath path: String,
                           completion: @escaping ((Result<Void, Error>) -> Void)) {
        sftpChannel
            .rmFile(path: path)
            .mapAsVoid()
            .whenComplete(on: updateQueue, completion)
    }

    public func close(completion: @escaping () -> Void) {
        sftpChannel
            .close()
            .whenComplete(on: updateQueue) { _ in
                completion()
            }
    }

    // MARK: - Private

    private func setupIOChannel() {
        sftpChannel.stateUpdateHandler = { [weak self] state in
            self?.updateQueue.async {
                self?.stateUpdateHandler?(state)
                switch state {
                case .idle:
                    break
                case .ready:
                    break
                case .closed:
                    self?.closeHandler?(nil)
                case .failed(let error):
                    self?.closeHandler?(error)
                }
            }
        }
    }

    private func recursivelyExecute<T, R>(_ future: @escaping (R) -> EventLoopFuture<T>,
                                          merge: @escaping (T, R) -> (R, Bool),
                                          response: R) -> EventLoopFuture<R> {
        let currentFuture = future(response)
        return currentFuture.flatMap { current in
            let (response, shouldContinue) = merge(current, response)
            if shouldContinue {
                return self.recursivelyExecute(
                    future,
                    merge: merge,
                    response: response
                )
            } else {
                return currentFuture.map { _ in response }
            }
        }
    }
}
