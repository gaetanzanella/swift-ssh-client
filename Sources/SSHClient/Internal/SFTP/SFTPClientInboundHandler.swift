import Foundation
import NIO
import NIOSSH

final class SFTPClientInboundHandler: ChannelInboundHandler {
    typealias InboundIn = SFTPMessage

    let onResponse: (SFTPResponse) -> Void

    init(onResponse: @escaping (SFTPResponse) -> Void) {
        self.onResponse = onResponse
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        if let response = SFTPResponse(message: message) {
            onResponse(response)
        } else {
            context.fireErrorCaught(SFTPError.invalidResponse)
        }
    }
}
