
import Foundation
import NIO
import NIOSSH

class StartShellHandler: ChannelInboundHandler {
    enum StartShellError: Error {
        case endedChannel
    }

    typealias InboundIn = SSHChannelData

    let handler: (Result<Void, Error>) -> Void

    // To avoid multiple starts
    private var isStarted = false

    init(handler: @escaping (Result<Void, Error>) -> Void) {
        self.handler = handler
    }

    deinit {
        triggerStart(.failure(StartShellError.endedChannel))
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context
            .channel
            .setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .flatMap {
                let promise = context.channel.eventLoop.makePromise(of: Void.self)
                let request = SSHChannelRequestEvent.ShellRequest(wantReply: true)
                context.triggerUserOutboundEvent(
                    request,
                    promise: promise
                )
                return promise.futureResult
            }
            .whenFailure { [weak self] error in
                self?.triggerStart(.failure(error))
            }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            triggerStart(.success(()))
        default:
            break
        }
        context.fireUserInboundEventTriggered(event)
    }

    private func triggerStart(_ result: Result<Void, Error>) {
        guard !isStarted else { return }
        isStarted = true
        handler(result)
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
