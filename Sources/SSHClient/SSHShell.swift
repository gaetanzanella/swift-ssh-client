import Foundation
import NIO
import NIOSSH

// TODO: Use proper state machine
public class SSHShell {
    public enum State {
        case idle, ready(Channel), closed, failed(SSHConnection.ConnectionError)
    }

    private var channel: Channel? {
        switch state {
        case .ready(let channel):
            return channel
        case .idle, .closed, .failed:
            return nil
        }
    }

    // TODO: Create a proper state machine
    private(set) var state: State = .idle
    private let updateQueue: DispatchQueue

    init(updateQueue: DispatchQueue) {
        self.updateQueue = updateQueue
    }

    public var onReadHandler: ((Data) -> Void)?
    public var onStateUpdateHandler: ((State) -> Void)?

    public func write(_ data: Data, completion: @escaping () -> Void) {
        guard let channel = channel else {
            completion()
            return
        }
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
        guard let channel = channel else {
            completion()
            return
        }
        channel.close().whenComplete { [weak self] _ in
            self?.onClose(error: nil)
            self?.updateQueue.async {
                completion()
            }
        }
    }

    // MARK: - Private

    private func onRead(_ data: Data) {
        updateQueue.async { [weak self] in
            self?.onReadHandler?(data)
        }
    }

    private func onClose(error: SSHConnection.ConnectionError?) {
        let old = state
        state = error.flatMap { .failed($0) } ?? .closed
        let new = state
        updateQueue.async { [weak self] in
            self?.onStateUpdateHandler?(new)
        }
    }
}

extension SSHShell: SSHSession {
    // MARK: - SSHSession

    func start(in context: SSHSessionContext) {
        state = .ready(context.channel)
        let result = context.channel.pipeline.addHandlers(
            [
                StartShellHandler(
                    eventLoop: context.channel.eventLoop
                ),
                ReadShellHandler(onData: { [weak self] in
                    self?.onRead($0)
                }),
                ErrorHandler(onClose: { [weak self] error in
                    self?.onClose(error: error)
                }),
            ]
        )
        .flatMap {
            context
                .channel
                .pipeline
                .handler(type: StartShellHandler.self)
                .flatMap {
                    $0.startPromise.futureResult
                }
        }
        .mapAsVoid()
        context.promise.completeWith(result)
    }
}
