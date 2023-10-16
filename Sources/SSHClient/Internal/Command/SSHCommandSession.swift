import Foundation
import NIO
import NIOSSH

class SSHCommandSession: SSHSession {
    private let invocation: SSHCommandInvocation

    private var promise: Promise<Void>?

    // MARK: - Life Cycle

    init(invocation: SSHCommandInvocation) {
        self.invocation = invocation
    }

    deinit {
        promise?.fail(SSHConnectionError.unknown)
    }

    // MARK: - SSHSession

    func start(in context: SSHSessionContext) {
        promise = context.promise
        let channel = context.channel
        channel.pipeline.addHandlers(
            [
                SSHCommandHandler(
                    invocation: invocation,
                    promise: context.promise
                ),
            ]
        )
        .whenFailure { error in
            context.promise.fail(error)
        }
    }
}

private class SSHCommandHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let invocation: SSHCommandInvocation
    private let promise: Promise<Void>

    private var isSuccess = false

    // MARK: - Life Cycle

    init(invocation: SSHCommandInvocation,
         promise: Promise<Void>) {
        self.invocation = invocation
        self.promise = promise
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let execRequest = SSHChannelRequestEvent.ExecRequest(
            command: invocation.command.command,
            wantReply: true
        )
        context
            .channel
//            .setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .eventLoop.flatSubmit {
                context.triggerUserOutboundEvent(execRequest)
            }
            .whenFailure { _ in
                context.channel.close(promise: nil)
            }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.channel.close(promise: nil)
        context.fireErrorCaught(error)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if isSuccess {
            promise.succeed(())
        } else {
            promise.fail(SSHShellError.unknown)
        }
        context.fireChannelInactive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        defer {
            context.fireUserInboundEventTriggered(event)
        }
        switch event {
        case let event as SSHChannelRequestEvent.ExitStatus:
            invocation.onStatus?(SSHCommandStatus(exitStatus: event.exitStatus))
        case let event as ChannelEvent:
            switch event {
            case .inputClosed:
                isSuccess = true
                context.channel.close(promise: nil)
            case .outputClosed:
                break
            }
        default:
            break
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        defer {
            context.fireChannelRead(data)
        }
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(var bytes) = channelData.data,
              let data = bytes.readData(length: bytes.readableBytes)
        else {
            fatalError("Unexpected read type")
        }
        switch channelData.type {
        case .channel:
            invocation.onChunk?(.init(channel: .standard, data: data))
        case .stdErr:
            invocation.onChunk?(.init(channel: .error, data: data))
        default:
            fatalError("Unexpected message type")
        }
    }
}
