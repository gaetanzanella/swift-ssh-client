import Foundation
import NIO
import NIOSSH

class SSHCommandSession: SSHSession {
    private let invocation: SSHCommandInvocation
    private let promise: Promise<SSHCommandStatus>

    var futureResult: Future<SSHCommandStatus> {
        promise.futureResult
    }

    // MARK: - Life Cycle

    init(invocation: SSHCommandInvocation,
         promise: Promise<SSHCommandStatus>) {
        self.invocation = invocation
        self.promise = promise
    }

    // MARK: - SSHSession

    func start(in context: SSHSessionContext) {
        let channel = context.channel
        let result = channel.pipeline.addHandlers(
            [
                SSHCommandHandler(
                    invocation: invocation,
                    promise: promise
                ),
            ]
        )
        context.promise.completeWith(result)
    }
}

private class SSHCommandHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let invocation: SSHCommandInvocation
    private let promise: Promise<SSHCommandStatus>

    // MARK: - Life Cycle

    init(invocation: SSHCommandInvocation,
         promise: Promise<SSHCommandStatus>) {
        self.invocation = invocation
        self.promise = promise
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { _ in
            context.close(promise: nil)
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        promise.fail(SSHConnectionError.unknown)
    }

    func channelActive(context: ChannelHandlerContext) {
        let execRequest = SSHChannelRequestEvent.ExecRequest(
            command: invocation.command.command,
            wantReply: invocation.wantsReply
        )
        context.triggerUserOutboundEvent(execRequest).whenFailure { _ in
            context.close(promise: nil)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let event as SSHChannelRequestEvent.ExitStatus:
            promise.succeed(
                SSHCommandStatus(exitStatus: event.exitStatus)
            )
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(var bytes) = channelData.data,
              let data = bytes.readData(length: bytes.readableBytes)
        else {
            fatalError("Unexpected read type")
        }
        switch channelData.type {
        case .channel:
            invocation.onChunk?(.init(channel: .standard, data: data))
            return
        case .stdErr:
            invocation.onChunk?(.init(channel: .error, data: data))
        default:
            fatalError("Unexpected message type")
        }
    }
}
