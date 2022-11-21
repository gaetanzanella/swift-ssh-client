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

final class SSHShellSession: SSHSession {

    struct Configuration {
        let updateQueue: DispatchQueue
    }

    let shell: SSHShell

    init(shell: SSHShell) {
        self.shell = shell
    }

    static func launch(on channel: Channel,
                       promise: Promise<SSHShellSession>,
                       configuration: Configuration) {
        let shell = SSHShell(channel: channel, updateQueue: configuration.updateQueue)
        let result = shell.channel.pipeline.addHandlers(
            [
                StartShellHandler(
                    eventLoop: channel.eventLoop
                ),
                ReadShellHandler(onData: { [weak shell] in
                    shell?.onRead($0)
                }),
                ErrorHandler(onClose: { [weak shell] error in
                    shell?.onClose(error: error)
                })
            ]
        )
        .flatMap {
            shell
                .channel
                .pipeline
                .handler(type: StartShellHandler.self)
                .flatMap {
                    $0.startPromise.futureResult
                }
        }
        .map {
            SSHShellSession(shell: shell)
        }
        promise.completeWith(result)
    }
}
