import Foundation
import NIO
import NIOSSH

public enum SSHConnectionError: Error {
    case requireActiveConnection
    case unknown
    case timeout
}

public class SSHConnection: @unchecked Sendable {
    public enum State: Sendable, Equatable {
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

    private let defaultTimeout: TimeInterval
    private var stateUpdateListeners = BlockObserverHolder<State>()

    private let ioConnection: IOSSHConnection
    private let updateQueue: DispatchQueue

    // MARK: - Life Cycle

    public init(host: String,
                port: UInt16,
                authentication: SSHAuthentication,
                defaultTimeout: TimeInterval = 15.0) {
        ioConnection = IOSSHConnection(
            host: host,
            port: port,
            authentication: authentication,
            eventLoopGroup: MultiThreadedEventLoopGroup.ssh
        )
        self.defaultTimeout = defaultTimeout
        updateQueue = DispatchQueue(label: "ssh_connection")
        setupIOConnection()
    }

    // MARK: - Connection

    public var stateUpdateHandler: ((State) -> Void)? {
        set {
            stateUpdateListeners.add(newValue, for: .publicAPI())
        }
        get {
            stateUpdateListeners.observer(for: .publicAPI())
        }
    }

    public func start(withTimeout timeout: TimeInterval? = nil,
                      completion: @escaping (Result<Void, Error>) -> Void) {
        ioConnection.start(timeout: timeout ?? defaultTimeout).whenComplete(on: updateQueue, completion)
    }

    public func cancel(completion: @escaping () -> Void) {
        ioConnection.cancel().whenComplete(on: updateQueue) { _ in
            completion()
        }
    }

    // MARK: - Clients

    @discardableResult
    public func requestShell(withTimeout timeout: TimeInterval? = nil,
                             completion: @escaping (Result<SSHShell, Error>) -> Void) -> SSHTask {
        let shell = SSHShell(
            ioShell: IOSSHShell(
                eventLoop: MultiThreadedEventLoopGroup.ssh.any()
            ),
            updateQueue: updateQueue
        )
        let task = SSHSessionStartingTask(
            session: shell,
            eventLoop: ioConnection.eventLoop
        )
        ioConnection.start(task, timeout: timeout ?? defaultTimeout)
            .map { shell }
            .whenComplete(on: updateQueue, completion)
        return task
    }

    @discardableResult
    public func requestSFTPClient(withTimeout timeout: TimeInterval? = nil,
                                  completion: @escaping (Result<SFTPClient, Error>) -> Void) -> SSHTask {
        let sftpClient = SFTPClient(
            sftpChannel: IOSFTPChannel(
                idAllocator: MonotonicRequestIDAllocator(start: 0),
                eventLoop: MultiThreadedEventLoopGroup.ssh.any()
            ),
            updateQueue: updateQueue
        )
        let task = SSHSessionStartingTask(
            session: sftpClient,
            eventLoop: ioConnection.eventLoop
        )
        ioConnection.start(task, timeout: timeout ?? defaultTimeout)
            .map { sftpClient }
            .whenComplete(on: updateQueue, completion)
        return task
    }

    // MARK: - Commands

    @discardableResult
    func execute(_ command: SSHCommand,
                 withTimeout timeout: TimeInterval? = nil,
                 onChunk: @escaping (SSHCommandChunk) -> Void,
                 onStatus: @escaping (SSHCommandStatus) -> Void,
                 completion: @escaping (Result<Void, Error>) -> Void) -> SSHTask {
        let invocation = SSHCommandInvocation(
            command: command,
            onChunk: { [weak self] chunk in
                self?.updateQueue.async {
                    onChunk(chunk)
                }
            },
            onStatus: { [weak self] st in
                self?.updateQueue.async {
                    onStatus(st)
                }
            }
        )
        let task = SSHSessionStartingTask(
            session: SSHCommandSession(invocation: invocation),
            eventLoop: ioConnection.eventLoop
        )
        ioConnection
            .start(task, timeout: timeout ?? defaultTimeout)
            .whenComplete(on: updateQueue, completion)
        return task
    }

    @discardableResult
    public func execute(_ command: SSHCommand,
                        withTimeout timeout: TimeInterval? = nil,
                        completion: @escaping (Result<SSHCommandResponse, Error>) -> Void) -> SSHTask {
        var standard: Data?
        var error: Data?
        var status: SSHCommandStatus?
        return execute(
            command,
            withTimeout: timeout,
            onChunk: { chunk in
                switch chunk.channel {
                case .standard:
                    if standard == nil {
                        standard = Data()
                    }
                    standard?.append(chunk.data)
                case .error:
                    if error == nil {
                        error = Data()
                    }
                    error?.append(chunk.data)
                }
            },
            onStatus: {
                status = $0
            },
            completion: { result in
                completion(result.mapThrowing { _ in
                    guard let status = status else { throw SSHConnectionError.unknown }
                    return SSHCommandResponse(
                        command: command,
                        status: status,
                        standardOutput: standard,
                        errorOutput: error
                    )
                })
            }
        )
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

import NIOTransportServices

private extension MultiThreadedEventLoopGroup {
    static let ssh = {
        // from https://github.com/swift-server/async-http-client/blob/main/Sources/AsyncHTTPClient/HTTPClient.swift#L110
        #if canImport(Network)
        return NIOTSEventLoopGroup()
        #else
        return MultiThreadedEventLoopGroup(numberOfThreads: 1)
        #endif
    }()
}
