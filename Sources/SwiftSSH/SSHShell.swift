import Foundation
import NIO
import NIOSSH

public class SSHShell {

    public enum State: Equatable {
        case ready, closed, failed(SSHConnection.ConnectionError)
    }

    let channel: Channel

    // TODO: Create a proper state machine
    private(set) var state: State = .ready
    private let updateQueue: DispatchQueue

    init(channel: Channel, updateQueue: DispatchQueue) {
        self.channel = channel
        self.updateQueue = updateQueue
    }

    public var onReadHandler: ((Data) -> Void)?
    public var onStateUpdateHandler: ((State) -> Void)?

    public func write(_ data: Data, completion: @escaping () -> Void) {
        let buffer = channel.allocator.buffer(data: data)
        channel.writeAndFlush(
            SSHChannelData(
                type: .channel,
                data: .byteBuffer(buffer)
            )
        )
        .whenComplete { [weak self] _ in
            self?.updateQueue.async {
                completion()
            }
        }
    }

    public func close(completion: @escaping () -> Void) {
        channel.close().whenComplete { [weak self] _ in
            self?.onClose(error: nil)
            self?.updateQueue.async {
                completion()
            }
        }
    }

    // MARK: - Private

    fileprivate func onRead(_ data: Data) {
        updateQueue.async { [weak self] in
            self?.onReadHandler?(data)
        }
    }

    fileprivate func onClose(error: SSHConnection.ConnectionError?) {
        let old = state
        state = error.flatMap { .failed($0) } ?? .closed
        let new = state
        guard old != new else { return }
        updateQueue.async { [weak self] in
            self?.onStateUpdateHandler?(new)
        }
    }
}

extension SSHShell {

    static func launch(on channel: Channel,
                       timeout: TimeInterval,
                       updateQueue: DispatchQueue) -> EventLoopFuture<SSHShell> {
        let shell = SSHShell(channel: channel, updateQueue: updateQueue)
        return shell.channel.pipeline.addHandlers(
            [
                StartShellHandler(
                    eventLoop: channel.eventLoop,
                    timeout: timeout
                ),
                ReadShellHandler(onData: { [weak shell] in
                    shell?.onRead($0)
                }),
                ErrorHandler(onClose: { [weak shell] error in
                    shell?.onClose(error: error)
                })
            ]
        )
        .map { shell }
    }
}
