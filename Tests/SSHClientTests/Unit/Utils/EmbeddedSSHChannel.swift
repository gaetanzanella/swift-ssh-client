
import Foundation
import XCTest
import NIOCore
import NIOEmbedded
import NIOSSH
@testable import SSHClient

class EmbeddedSSHChannel {

    var channel: Channel {
        embeddedChannel
    }

    var loop: EmbeddedEventLoop {
        embeddedChannel.embeddedEventLoop
    }

    var outboundEvents: [AnyHashable] {
        recorder.userOutboundEvents
    }

    var isActive: Bool {
        embeddedChannel.isActive
    }

    private var recorder = ChannelRecorder()
    private let embeddedChannel = EmbeddedChannel()

    var shouldFailOnOutboundEvent: Bool {
        set { recorder.shouldFailOnOutboundEvent = newValue }
        get { recorder.shouldFailOnOutboundEvent }
    }

    func triggerInbound(_ event: Any) {
        embeddedChannel.pipeline.fireUserInboundEventTriggered(event)
    }

    func startMonitoringOutbound() throws {
        try channel.pipeline.addHandler(recorder).wait()
    }

    func triggerInboundChannelString(_ string: String) -> Data {
        let data = string.data(using: .utf8)!
        channel.pipeline.fireChannelRead(
            NIOAny(SSHChannelData(type: .channel, data: .byteBuffer(.init(data: data))))
        )
        return data
    }

    func triggerInboundSTDErrString(_ string: String) -> Data {
        let data = string.data(using: .utf8)!
        channel.pipeline.fireChannelRead(
            NIOAny(SSHChannelData(type: .stdErr, data: .byteBuffer(.init(data: data))))
        )
        return data
    }

    func readOutbound() throws -> SSHChannelData? {
        return try embeddedChannel.readOutbound(as: SSHChannelData.self)
    }

    func readAllOutbound() throws -> [SSHChannelData] {
        var result: [SSHChannelData] = []
        while let data = try readOutbound() {
            result.append(data)
        }
        return result
    }

    func connect() -> Future<Void> {
        return channel.connect(to: try! .init(unixDomainSocketPath: "/fake"))
    }

    func close() -> Future<Void> {
        return channel.close()
    }

    func run() {
        loop.run()
    }
}

private class ChannelRecorder: ChannelDuplexHandler {
    typealias OutboundIn = SSHChannelData
    typealias InboundIn = NIOAny

    private(set) var userOutboundEvents: [AnyHashable] = []
    private(set) var userInboundEvents: [AnyHashable] = []

    var shouldFailOnOutboundEvent = false

    func triggerUserOutboundEvent(context: ChannelHandlerContext,
                                  event: Any,
                                  promise: EventLoopPromise<Void>?) {
        if let event = event as? (any Hashable) {
            userOutboundEvents.append(AnyHashable(event))
        }
        if shouldFailOnOutboundEvent {
            struct AnError: Error {}
            promise?.fail(AnError())
        } else {
            promise?.succeed(())
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? (any Hashable) {
            userInboundEvents.append(AnyHashable(event))
        }
        context.fireUserInboundEventTriggered(event)
    }
}
