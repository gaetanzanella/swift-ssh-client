import Foundation
import NIOCore
import NIOSSH

class IOSSHShell {
    private var stateMachine: SSHShellStateMachine
    private let eventLoop: EventLoop

    var state: SSHShell.State {
        stateMachine.state
    }

    var stateUpdateHandler: ((SSHShell.State) -> Void)?
    var readHandler: ((Data) -> Void)?

    // MARK: - Life Cycle

    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
        stateMachine = SSHShellStateMachine()
    }

    // MARK: - Public

    func start(in context: SSHSessionContext) {
        context.channel.eventLoop.execute {
            self.trigger(.requestStart(context.channel, context.promise))
        }
    }

    func write(_ data: Data) -> Future<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        return eventLoop.submit {
            self.trigger(.requestWrite(data, promise))
        }
        .flatMap { _ in
            promise.futureResult
        }
    }

    func close() -> Future<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        return eventLoop.submit {
            self.trigger(.requestClosing(promise))
        }
        .flatMap { _ in
            promise.futureResult
        }
    }

    // MARK: - Private

    private func trigger(_ event: SSHShellEvent) {
        let old = stateMachine.state
        let action = stateMachine.handle(event)
        let new = stateMachine.state
        if old != new {
            stateUpdateHandler?(new)
        }
        handle(action)
    }

    private func handle(_ action: SSHShellAction) {
        switch action {
        case .write(let data, let channel, let promise):
            write(data, channel: channel, promise: promise)
        case .close(let channel):
            close(channel)
        case .start(let channel):
            startShell(channel)
        case .dataAvailable(let data):
            readHandler?(data)
        case .callPromise(let promise, let result):
            promise.end(result)
        case .none:
            break
        }
    }

    private func close(_ channel: Channel) {
        channel.close(promise: nil)
    }

    private func write(_ data: Data,
                       channel: Channel,
                       promise: Promise<Void>) {
        let buffer = channel.allocator.buffer(data: data)
        let result = channel.writeAndFlush(
            SSHChannelData(
                type: .channel,
                data: .byteBuffer(buffer)
            )
        )
        promise.completeWith(result)
    }

    private func startShell(_ channel: Channel) {
        _ = channel.pipeline.addHandlers(
            [
                StartShellHandler(
                    handler: { [weak self] in
                        self?.trigger(.started)
                    }
                ),
                ReadShellHandler(onData: { [weak self] data in
                    self?.trigger(.read(data))
                }),
                NIOCloseOnErrorHandler(),
            ]
        )
        .flatMapError { _ in
            // we close the channel in case of error
            channel.closeFuture
        }
        channel.closeFuture.whenComplete { [weak self] _ in
            self?.trigger(.closed)
        }
    }
}
