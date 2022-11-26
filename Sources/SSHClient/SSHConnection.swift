import Foundation
import NIO
import NIOSSH

public enum SSHConnectionError: Error {
    case requireActiveConnection
    case unknown
    case timeout
}

public class SSHConnection {
    public enum State: Equatable {
        case idle, ready, failed(SSHConnectionError)
    }

    public var state: SSHConnection.State {
        ioConnection.state
    }

    public var authentication: SSHAuthentication {
        ioConnection.authentication
    }

    public var host: String {
        ioConnection.host
    }

    public var port: UInt16 {
        ioConnection.port
    }

    private let ioConnection: IOSSHConnection
    private let updateQueue: DispatchQueue

    // MARK: - Life Cycle

    public init(host: String,
                port: UInt16,
                authentication: SSHAuthentication,
                updateQueue: DispatchQueue = .main) {
        ioConnection = IOSSHConnection(
            host: host,
            port: port,
            authentication: authentication,
            eventLoopGroup: MultiThreadedEventLoopGroup.ssh
        )
        self.updateQueue = updateQueue
        setupIOConnection()
    }

    // MARK: - Connection

    public var stateUpdateHandler: ((State) -> Void)?

    public func start(withTimeout timeout: TimeInterval,
                      completion: @escaping (Result<Void, Error>) -> Void) {
        ioConnection.start(timeout: timeout).whenComplete(on: updateQueue, completion)
    }

    public func cancel(completion: @escaping () -> Void) {
        ioConnection.cancel().whenComplete(on: updateQueue) { _ in
            completion()
        }
    }

    // MARK: - Clients

    public func requestShell(withTimeout timeout: TimeInterval,
                             updateQueue: DispatchQueue = .main,
                             completion: @escaping (Result<SSHShell, Error>) -> Void) {
        let shell = SSHShell(
            ioShell: IOSSHShell(
                eventLoop: MultiThreadedEventLoopGroup.ssh.any()
            ),
            updateQueue: updateQueue
        )
        ioConnection.start(shell, timeout: timeout)
            .map { shell }
            .whenComplete(on: updateQueue, completion)
    }

    public func requestSFTPClient(withTimeout timeout: TimeInterval,
                                  updateQueue: DispatchQueue = .main,
                                  completion: @escaping (Result<SFTPClient, Error>) -> Void) {
        let sftpClient = SFTPClient(
            sftpChannel: IOSFTPChannel(
                idAllocator: MonotonicRequestIDAllocator(start: 0),
                eventLoop: MultiThreadedEventLoopGroup.ssh.any()
            ),
            updateQueue: updateQueue
        )
        ioConnection.start(sftpClient, timeout: timeout)
            .map { sftpClient }
            .whenComplete(on: updateQueue, completion)
    }

    // MARK: - Commands

    public func execute(_ command: SSHCommand,
                        withTimeout timeout: TimeInterval,
                        completion: @escaping (Result<SSHCommandStatus, Error>) -> Void) {
        var status: SSHCommandStatus?
        ioConnection.execute(
            SSHCommandInvocation(
                command: command,
                wantsReply: false,
                onChunk: nil,
                onStatus: { st in status = st }
            ),
            timeout: timeout
        )
        .whenComplete(on: updateQueue) { result in
            completion(result.flatMap { _ in
                Result(catching: {
                    if let status = status {
                        return status
                    }
                    throw SSHConnectionError.unknown
                })
            })
        }
    }

    public func stream(_ command: SSHCommand,
                       withTimeout timeout: TimeInterval,
                       onChunk: @escaping (SSHCommandChunk) -> Void,
                       onStatus: @escaping (SSHCommandStatus) -> Void,
                       completion: @escaping (Result<Void, Error>) -> Void) {
        ioConnection.execute(
            SSHCommandInvocation(
                command: command,
                wantsReply: true,
                onChunk: onChunk,
                onStatus: onStatus
            ),
            timeout: timeout
        )
        .whenComplete(on: updateQueue, completion)
    }

    public func capture(_ command: SSHCommand,
                        withTimeout timeout: TimeInterval,
                        completion: @escaping (Result<SSHCommandCapture, Error>) -> Void) {
        var standard: Data?
        var error: Data?
        var status: SSHCommandStatus?
        ioConnection.execute(
            SSHCommandInvocation(
                command: command,
                wantsReply: true,
                onChunk: { chunk in
                    switch chunk.channel {
                    case .standard:
                        if (standard == nil) {
                            standard = Data()
                        }
                        standard?.append(chunk.data)
                    case .error:
                        if (error == nil) {
                            error = Data()
                        }
                        error?.append(chunk.data)
                    }
                },
                onStatus: { st in status = st }
            ),
            timeout: timeout
        )
        .whenComplete(on: updateQueue) { result in
            completion(result.map { response in
                SSHCommandCapture(
                    command: command,
                    standardOutput: standard,
                    errorOutput: error,
                    status: status
                )
            })
        }
    }

    // MARK: - Private

    private func setupIOConnection() {
        ioConnection.stateUpdateHandler = { [weak self] state in
            self?.updateQueue.async {
                self?.stateUpdateHandler?(state)
            }
        }
    }
}

private extension MultiThreadedEventLoopGroup {
    static let ssh = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}
