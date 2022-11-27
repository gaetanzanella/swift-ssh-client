
import Crypto
import Dispatch
import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SSHClient

class IOSSHServer: SSHServer {
    private(set) var receivedBuffer = Data()

    let username: String
    let password: String
    let host: String
    let port: UInt16

    var timeBeforeAuthentication: TimeInterval = 0.0

    private(set) var authenticationCount = 0

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    private var channel: Channel?
    private var child: Channel?

    var hasActiveChild: Bool {
        child?.isActive ?? false
    }

    init(expectedUsername: String,
         expectedPassword: String,
         host: String,
         port: UInt16) {
        username = expectedUsername
        password = expectedPassword
        self.host = host
        self.port = port
    }

    func end() {
        _ = try! channel?.close().wait()
        group.shutdownGracefully { _ in }
        channel = nil
        child = nil
    }

    func waitClosing() {
        try? channel?.closeFuture.wait()
    }

    func run() throws {
        let hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        let bootstrap = ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                self.child = channel
                return channel.pipeline.addHandlers(
                    [
                        NIOSSHHandler(
                            role: .server(.init(
                                hostKeys: [hostKey],
                                userAuthDelegate: HardcodedPasswordDelegate(
                                    expectedUsername: self.username,
                                    expectedPassword: self.password,
                                    hasReceivedRequest: {
                                        self.authenticationCount += 1
                                    },
                                    timeBeforeAuthentication: { self.timeBeforeAuthentication }
                                )
                            )),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: self.sshChildChannelInitializer(_:channelType:)
                        ),
                    ]
                )
            }
            .serverChannelOption(
                ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR),
                value: 1
            )
            .serverChannelOption(
                ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY),
                value: 1
            )

        channel = try bootstrap.bind(host: "0.0.0.0", port: Int(port)).wait()
    }

    private func sshChildChannelInitializer(_ channel: Channel,
                                            channelType: SSHChannelType) -> EventLoopFuture<Void> {
        switch channelType {
        case .session:
            child = channel
            return channel.pipeline.addHandler(
                ExampleExecHandler()
            )
        case .directTCPIP, .forwardedTCPIP:
            fatalError("NOT AVAILABLE")
        }
    }
}

enum SSHServerError: Error {
    case invalidCommand
    case invalidDataType
    case invalidChannelType
    case alreadyListening
    case notListening
}

class ExampleExecHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    let queue = DispatchQueue(label: "background exec")

    var response = "DONE"
    var timeBeforeAnswer: TimeInterval = 2.0

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { error in
            context.fireErrorCaught(error)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        context.fireChannelInactive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let event as SSHChannelRequestEvent.ExecRequest:
            let buffer = context.channel.allocator.buffer(string: response)
            queue.asyncAfter(deadline: .now() + timeBeforeAnswer) {
                context.write(
                    self.wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer)))
                )
                .whenComplete { result in
                    guard event.wantReply else { return }
                    switch result {
                    case .failure:
                        context.channel.triggerUserOutboundEvent(ChannelFailureEvent(), promise: nil)
                    case .success:
                        context.channel.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
                    }
                }
            }
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = unwrapInboundIn(data)

        guard case .byteBuffer(let bytes) = data.data else {
            fatalError("Unexpected read type")
        }

        guard case .channel = data.type else {
            context.fireErrorCaught(SSHServerError.invalidDataType)
            return
        }

        context.fireChannelRead(wrapInboundOut(bytes))
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let data = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(data))), promise: promise)
    }
}

class HardcodedPasswordDelegate: NIOSSHServerUserAuthenticationDelegate {
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods {
        .password
    }

    let username: String
    let password: String
    let timeBeforeAuthentication: () -> TimeInterval
    let hasReceivedRequest: () -> Void

    init(expectedUsername: String,
         expectedPassword: String,
         hasReceivedRequest: @escaping () -> Void,
         timeBeforeAuthentication: @escaping () -> TimeInterval) {
        username = expectedUsername
        password = expectedPassword
        self.hasReceivedRequest = hasReceivedRequest
        self.timeBeforeAuthentication = timeBeforeAuthentication
    }

    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        hasReceivedRequest()
        guard request.username == username, case .password(let passwordRequest) = request.request else {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeBeforeAuthentication()) {
                responsePromise.succeed(.failure)
            }
            return
        }

        if passwordRequest.password == password {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeBeforeAuthentication()) {
                responsePromise.succeed(.success)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeBeforeAuthentication()) {
                responsePromise.succeed(.failure)
            }
        }
    }
}
