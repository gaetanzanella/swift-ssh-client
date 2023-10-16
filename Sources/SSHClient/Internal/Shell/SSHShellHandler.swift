
import Foundation
import NIO
import NIOSSH

class StartShellHandler: ChannelInboundHandler {
    enum StartShellError: Error {
        case endedChannel
    }

    typealias InboundIn = SSHChannelData

    let handler: () -> Void

    // To avoid multiple starts
    private var isStarted = false

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    deinit {}

    func handlerAdded(context: ChannelHandlerContext) {
        _ = context
            .channel
            .eventLoop
            // TODO: (gz): Move option to bootstrapper
            // https://forums.swift.org/t/unit-testing-channeloptions/51797
            // .setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .flatSubmit {
                let promise = context.channel.eventLoop.makePromise(of: Void.self)
                let request = SSHChannelRequestEvent.ShellRequest(wantReply: true)
                context.triggerUserOutboundEvent(
                    request,
                    promise: promise
                )
                return promise.futureResult
            }
            .flatMapError { _ in
                // we close the channel in case of error
                context
                    .channel
                    .close()
            }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            triggerStart()
        default:
            break
        }
        context.fireUserInboundEventTriggered(event)
    }

    private func triggerStart() {
        guard !isStarted else { return }
        isStarted = true
        handler()
    }
}

class ReadShellHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    let onData: (Data) -> Void

    init(onData: @escaping (Data) -> Void) {
        self.onData = onData
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let sshData = unwrapInboundIn(data)
        guard case .byteBuffer(var buffer) = sshData.data, let bytes = buffer.readData(length: buffer.readableBytes) else {
            return
        }
        switch sshData.type {
        case .channel:
            onData(bytes)
        case .stdErr:
            onData(bytes)
        default:
            break
        }
        context.fireChannelRead(data)
    }
}
