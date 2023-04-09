
import Foundation
import NIO
import NIOSSH
import NIOTransportServices

class IOSSHConnection {
    let authentication: SSHAuthentication
    let host: String
    let port: UInt16

    private var stateMachine: SSHConnectionStateMachine
    private let eventLoopGroup: EventLoopGroup

    private var eventLoop: EventLoop {
        eventLoopGroup.any()
    }

    var state: SSHConnection.State {
        stateMachine.state
    }

    var stateUpdateHandler: ((SSHConnection.State) -> Void)?

    // MARK: - Life Cycle

    init(host: String,
         port: UInt16,
         authentication: SSHAuthentication,
         eventLoopGroup: EventLoopGroup) {
        self.host = host
        self.port = port
        self.authentication = authentication
        self.eventLoopGroup = eventLoopGroup
        stateMachine = SSHConnectionStateMachine()
    }

    // MARK: - Public

    func start(timeout: TimeInterval) -> Future<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        return eventLoop.submit {
            self.trigger(.requestConnection(timeout, promise))
        }
        .flatMap {
            promise.futureResult
        }
    }

    func cancel() -> Future<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        return eventLoop.submit {
            self.trigger(.requestDisconnection(promise))
        }
        .flatMap {
            promise.futureResult
        }
    }

    func start(_ session: SSHSession,
               timeout: TimeInterval) -> Future<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        return eventLoop.submit {
            self.trigger(.requestSession(session, timeout, promise))
        }
        .flatMap {
            promise.futureResult
        }
        .map {
            // TODO: Fix hack. We keep the session alive as long as the promise is running.
            session
        }
        .mapAsVoid()
    }

    // MARK: - Private

    private func trigger(_ event: SSHConnectionEvent) {
        let old = stateMachine.state
        let action = stateMachine.handle(event)
        let new = stateMachine.state
        if old != new {
            stateUpdateHandler?(new)
        }
        handle(action)
    }

    private func handle(_ action: SSHConnectionAction) {
        switch action {
        case .connect(let timeout):
            connect(timeout: timeout)
        case .disconnect(let channel):
            disconnect(channel: channel)
        case .requestSession(let channel, let session, let timeout, let promise):
            startSession(channel: channel, session: session, timeout: timeout, promise: promise)
        case .callPromise(let promise, let result):
            promise.end(result)
        case .none:
            break
        }
    }

    private func connect(timeout: TimeInterval) {
        var clientConfiguration = SSHClientConfiguration(
            userAuthDelegate: BuiltInSSHAuthenticationValidator(
                authentication: authentication
            ),
            serverAuthDelegate: BuiltInSSHClientServerAuthenticationValidator(
                validation: authentication.hostKeyValidation
            )
        )
        clientConfiguration.transportProtectionSchemes = []
        for scheme in authentication.transportProtection.schemes {
            switch scheme {
            case .aes128CTR:
                clientConfiguration.transportProtectionSchemes.append(
                    AES128CTRTransportProtection.self
                )
            case .bundled:
                clientConfiguration.transportProtectionSchemes.append(
                    contentsOf: Constants.bundledTransportProtectionSchemes
                )
            case .custom(let protection):
                clientConfiguration.transportProtectionSchemes.append(protection)
            }
        }
        let clientBootstrap: NIOClientTCPBootstrapProtocol
        #if canImport(Network)
        clientBootstrap = NIOTSConnectionBootstrap(group: eventLoopGroup)
            .channelOption(NIOTSChannelOptions.waitForActivity, value: false)
        #else
        clientBootstrap = ClientBootstrap(group: eventLoopGroup)
        #endif
        let bootstrap = clientBootstrap.channelInitializer { channel in
            channel.pipeline.addHandlers([
                NIOSSHHandler(
                    role: .client(clientConfiguration),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                ),
                SSHAuthenticationHandler(
                    eventLoop: self.eventLoop,
                    timeout: .seconds(Int64(timeout))
                ),
                NIOCloseOnErrorHandler(),
            ])
        }
        .connectTimeout(.seconds(Int64(timeout)))
        .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
        let channel = bootstrap.connect(host: host, port: Int(port))
            .flatMap { [weak self] channel -> EventLoopFuture<Channel> in
                self?.trigger(.connected(channel))
                return channel
                    .pipeline.handler(type: SSHAuthenticationHandler.self)
                    .flatMap {
                        $0.authenticated
                    }
                    .map { channel }
                    .flatMapError { error in
                        // we close the created channel and spread the error
                        channel
                            .close()
                            .flatMapThrowing {
                                throw error
                            }
                    }
            }
        channel.whenSuccess { [weak self] channel in
            channel.closeFuture.whenComplete { _ in
                self?.trigger(.disconnected)
            }
            self?.trigger(.authenticated(channel))
        }
        channel.whenFailure { [weak self] _ in
            self?.trigger(.disconnected)
        }
    }

    private func disconnect(channel: Channel) {
        channel.close(promise: nil)
    }

    private func startSession(channel: Channel,
                              session: SSHSession,
                              timeout: TimeInterval,
                              promise: Promise<Void>) {
        let createChannel = channel.eventLoop.makePromise(of: Channel.self)
        channel.eventLoop.scheduleTask(in: .seconds(Int64(timeout))) {
            createChannel.fail(SSHConnectionError.timeout)
        }
        let result = channel
            .pipeline
            .handler(type: NIOSSHHandler.self)
            .flatMap { handler in
                handler.createChannel(createChannel, channelType: .session, nil)
                return createChannel
                    .futureResult
                    .flatMap { channel in
                        let createSession = channel.eventLoop.makePromise(of: Void.self)
                        // TODO: We should only consider the remaining time, but that's ok
                        channel.eventLoop.scheduleTask(in: .seconds(Int64(timeout))) {
                            createSession.fail(SSHConnectionError.timeout)
                        }
                        session.start(
                            in: SSHSessionContext(
                                channel: channel,
                                promise: createSession
                            )
                        )
                        return createSession.futureResult
                    }
                    .flatMapError { error in
                        // we close the created channel and spread the error
                        channel
                            .close()
                            .flatMapThrowing {
                                throw error
                            }
                    }
            }
        promise.completeWith(result)
    }
}
