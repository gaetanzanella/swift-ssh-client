import Foundation
import NIO
import NIOSSH

public class SSHConnection {

    public enum ConnectionError: Error {
        case requireActiveConnection
        case unknown
        case timeout
    }

    public enum State: Equatable {
        case idle, ready, failed(ConnectionError)
    }

    public var state: SSHConnection.State {
        stateMachine.state
    }

    public let authentication: SSHAuthentication
    public let host: String
    public let port: UInt16

    private var stateMachine = SSHConnectionStateMachine()
    private var channel: Channel? {
        stateMachine.channel
    }

    private let eventLoop = MultiThreadedEventLoopGroup.ssh.next()
    private let updateQueue: DispatchQueue

    // MARK: - Life Cycle

    public init(host: String,
                port: UInt16,
                authentication: SSHAuthentication,
                updateQueue: DispatchQueue = .main) {
        self.authentication = authentication
        self.host = host
        self.port = port
        self.updateQueue = updateQueue
    }

    // MARK: - Public

    public var stateUpdateHandler: ((State) -> Void)?

    public func start(withTimeout timeout: TimeInterval,
                      completion: @escaping (Result<Void, Error>) -> Void) {
        eventLoop.execute {
            self.updateState(
                event: .requestConnection(
                    timeout,
                    { error in completion(error.flatMap { .failure($0) } ?? .success(())) }
                )
            )
        }
    }

    public func end(completion: @escaping () -> Void) {
        eventLoop.execute {
            self.updateState(event: .requestDisconnection(completion))
        }
    }

    public func requestShell(withTimeout timeout: TimeInterval,
                             updateQueue: DispatchQueue = .main,
                             completion: @escaping (Result<SSHShell, Error>) -> Void) {
        start(SSHShellSession.self, timeout: timeout, configuration: .init(updateQueue: updateQueue))
            .map { $0.shell }
            .whenComplete(on: updateQueue, completion)
    }

    public func requestSFTPClient(withTimeout timeout: TimeInterval,
                                  updateQueue: DispatchQueue = .main,
                                  completion: @escaping (Result<SFTPClient, Error>) -> Void) {
        start(SFTPSession.self, timeout: timeout, configuration: .init(updateQueue: updateQueue))
            .map { $0.client }
            .whenComplete(on: updateQueue, completion)
    }

    // MARK: - Private

    private func updateState(event: SSHConnectionEvent) {
        let old = stateMachine.state
        let action = stateMachine.handle(event)
        let new = stateMachine.state
        if old != new {
            updateQueue.async { [weak self] in
                self?.stateUpdateHandler?(new)
            }
        }
        switch action {
        case let .connect(timeout):
            connect(timeout: timeout)
        case let .disconnect(channel):
            disconnect(channel: channel)
        case let .callErrorCompletion(list, error):
            updateQueue.async {
                list.forEach { $0(error) }
            }
        case let .callCompletion(list):
            updateQueue.async {
                list.forEach { $0(()) }
            }
        case .none:
            break
        }
    }

    private func start<Session: SSHSession>(_ session: Session.Type,
                                            timeout: TimeInterval,
                                            configuration: Session.Configuration) -> Future<Session> {
        eventLoop
            .submit { () throws -> Channel in
                if let channel = self.channel {
                    return channel
                } else {
                    throw ConnectionError.requireActiveConnection
                }
            }
            .flatMap { channel in
                let createChannel = channel.eventLoop.makePromise(of: Channel.self)
                channel.eventLoop.scheduleTask(in: .seconds(Int64(timeout))) {
                    createChannel.fail(ConnectionError.timeout)
                }
                return channel
                    .pipeline
                    .handler(type: NIOSSHHandler.self)
                    .flatMap { handler in
                        handler.createChannel(createChannel, channelType: .session, nil)
                        return createChannel
                            .futureResult
                            .flatMap { channel in
                                let createSession = channel.eventLoop.makePromise(of: Session.self)
                                channel.eventLoop.scheduleTask(in: .seconds(Int64(timeout))) {
                                    createSession.fail(ConnectionError.timeout)
                                }
                                Session.launch(
                                    on: channel,
                                    promise: createSession,
                                    configuration: configuration
                                )
                                return createSession.futureResult
                            }
                            .map { (client: Session) in
                                return client
                            }
                            .flatMapError { error in
                                // we close the created channel and spread the error
                                return channel
                                    .close()
                                    .flatMapThrowing { _ -> Session in
                                        throw error
                                    }
                            }
                    }
            }
    }

    private func connect(timeout: TimeInterval) {
        let group: MultiThreadedEventLoopGroup = .ssh
        var clientConfiguration = SSHClientConfiguration(
            userAuthDelegate: BuiltInSSHAuthenticationValidator(
                authentication: authentication
            ),
            serverAuthDelegate: BuiltInSSHClientServerAuthenticationValidator(
                validation: authentication.hostKeyValidation
            )
        )
        clientConfiguration.transportProtectionSchemes.append(LegacyTransportProtection.self)
        let bootstrap = ClientBootstrap(group: group).channelInitializer { channel in
            channel.pipeline.addHandlers([
                NIOSSHHandler(
                    role: .client(clientConfiguration),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                ),
                SSHAuthenticationHandler(
                    eventLoop: group.next(),
                    timeout: .seconds(Int64(timeout))
                ),
                ErrorHandler { [weak self] error in
                    self?.updateState(
                        event: .error(error)
                    )
                }
            ])
        }
            .connectTimeout(.seconds(Int64(timeout)))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
        let channel = bootstrap.connect(host: host, port: Int(port))
            .flatMap { [weak self] channel -> EventLoopFuture<Channel> in
                self?.updateState(event: .connected(channel))
                return channel
                    .pipeline.handler(type: SSHAuthenticationHandler.self)
                    .flatMap {
                        $0.authenticated
                    }
                    .map { channel }
            }
        channel
            .whenComplete { [weak self] result in
                switch result {
                case .failure(SSHAuthenticationHandler.AuthenticationError.endedChannel):
                    break
                case .failure(SSHAuthenticationHandler.AuthenticationError.timeout):
                    self?.updateState(event: .error(.timeout))
                case let .failure(error):
                    self?.updateState(event: .error((error as? SSHConnection.ConnectionError) ?? .unknown))
                case let .success(channel):
                    self?.updateState(event: .authenticated(channel))
                }
            }
        channel.flatMap {
            $0.closeFuture
        }
        .whenComplete { [weak self] _ in
            self?.updateState(event: .disconnected)
        }
    }

    private func disconnect(channel: Channel) {
        _ = channel.close()
    }
}

extension MultiThreadedEventLoopGroup {

    static let ssh = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}
