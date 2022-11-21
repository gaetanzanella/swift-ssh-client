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
        schedule { [weak self] in
            self?.updateState(
                event: .requestConnection(
                    timeout,
                    { error in completion(error.flatMap { .failure($0) } ?? .success(())) }
                )
            )
        }
    }

    public func end(completion: @escaping () -> Void) {
        schedule { [weak self] in
            self?.updateState(event: .requestDisconnection(completion))
        }
    }

    public func requestShell(withTimeout timeout: TimeInterval,
                             updateQueue: DispatchQueue = .main,
                             completion: @escaping (Result<SSHShell, Error>) -> Void) {
        schedule { [weak self] in
            self?.triggerShellStart(withTimeout: timeout, updateQueue: updateQueue, completion: completion)
        }
    }

    public func requestSFTPClient(withTimeout timeout: TimeInterval,
                                  updateQueue: DispatchQueue = .main,
                                  completion: @escaping (Result<SFTPClient, Error>) -> Void) {
        schedule { [weak self] in
            self?.triggerSFTP(
                withTimeout: timeout,
                updateQueue: updateQueue,
                completion: completion
            )
        }
    }

    // MARK: - Private

    private func schedule(_ task: @escaping () -> Void) {
        MultiThreadedEventLoopGroup.ssh.next().execute {
            task()
        }
    }

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

    private func triggerShellStart(withTimeout timeout: TimeInterval,
                                   updateQueue: DispatchQueue,
                                   completion: @escaping (Result<SSHShell, Error>) -> Void) {
        guard let root = channel else {
            updateQueue.async {
                completion(.failure(ConnectionError.requireActiveConnection))
            }
            return
        }
        let creationPromise = root.eventLoop.makePromise(of: Channel.self)
        let channel = root
            .pipeline
            .handler(type: NIOSSHHandler.self)
            .flatMap { handler in
                handler.createChannel(
                    creationPromise,
                    channelType: .session,
                    nil
                )
                return creationPromise.futureResult
            }
            .flatMap { (channel: Channel) -> EventLoopFuture<SSHShell> in
                return SSHShell.launch(on: channel, timeout: timeout, updateQueue: updateQueue)
            }
            .flatMap { shell in
                shell
                    .channel
                    .pipeline
                    .handler(type: StartShellHandler.self)
                    .flatMap {
                        $0.startPromise.futureResult
                    }
                    .map {
                        shell
                    }
            }
        channel.whenComplete { [weak self] result in
            let r = result
            self?.updateQueue.async {
                completion(r)
                return
            }
        }
    }

    private func triggerSFTP(withTimeout timeout: TimeInterval,
                             updateQueue: DispatchQueue,
                             completion: @escaping (Result<SFTPClient, Error>) -> Void) {
        guard let channel = channel else {
            updateQueue.async {
                completion(.failure(ConnectionError.requireActiveConnection))
            }
            return
        }
        let createChannel = channel.eventLoop.makePromise(of: Channel.self)
        let createClient = channel.eventLoop.makePromise(of: SFTPClient.self)
        let timeoutCheck = channel.eventLoop.makePromise(of: Void.self)
        channel.eventLoop.scheduleTask(in: .seconds(Int64(timeout))) {
            // TODO Close potential created channel
            timeoutCheck.fail(SFTPError.missingResponse)
            createChannel.fail(SFTPError.missingResponse)
            createClient.fail(SFTPError.missingResponse)
        }
        channel
            .pipeline
            .handler(type: NIOSSHHandler.self)
            .flatMap { handler in
                handler.createChannel(createChannel, nil)
                return createChannel
                    .futureResult
                    .flatMap { channel in
                        let openSubsystem = channel.eventLoop.makePromise(of: Void.self)
                        channel.triggerUserOutboundEvent(
                            SSHChannelRequestEvent.SubsystemRequest(
                                subsystem: "sftp",
                                wantReply: true
                            ),
                            promise: openSubsystem
                        )
                        return openSubsystem.futureResult.map { channel }
                    }
                    .flatMap { (channel: Channel) in
                        return channel.pipeline.addHandlers(
                            [
                                SSHChannelDataUnwrapper(),
                                SSHOutboundChannelDataWrapper()
                            ]
                        )
                        .map { channel }
                    }
                    .flatMap { channel in
                        IOSFTPChannel.launch(on: channel)
                    }
                    .map { sftpChannel in
                        SFTPClient(
                            sftpChannel: sftpChannel,
                            updateQueue: updateQueue
                        )
                    }
                    .map { (client: SFTPClient) in
                        timeoutCheck.succeed(())
                        return client
                    }
            }
            .whenComplete { [weak self] result in
                self?.updateQueue.async {
                    completion(result)
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
        .whenComplete { [weak self] result in
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

