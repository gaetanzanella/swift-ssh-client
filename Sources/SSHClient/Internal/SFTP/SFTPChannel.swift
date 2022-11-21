
import Foundation
import NIO
import NIOCore

protocol SFTPChannel {
    func close() -> Future<Void>

    func openFile(_ file: SFTPMessage.OpenFile.Payload) -> Future<SFTPMessage.Handle>
    func closeFile(_ file: SFTPFileHandle) -> Future<SFTPMessage.Status>
    func readFile(_ file: SFTPMessage.ReadFile.Payload) -> Future<SFTPMessage.ReadFile.Response>
    func writeFile(_ file: SFTPMessage.WriteFile.Payload) -> Future<SFTPMessage.Status>
    func mkdir(_ dir: SFTPMessage.MkDir.Payload) -> Future<SFTPMessage.Status>
    func rmdir(path: String) -> Future<SFTPMessage.Status>
    func rmFile(path: String) -> Future<SFTPMessage.Status>
    func readDir(_ handle: SFTPFileHandle) -> Future<SFTPMessage.ReadDir.Response>
    func openDir(path: String) -> Future<SFTPMessage.Handle>
    func realpath(path: String) -> Future<SFTPMessage.Name>
    func stat(path: String) -> Future<SFTPMessage.Attributes>
    func rename(_ payload: SFTPMessage.Rename.Payload) -> Future<SFTPMessage.Status>
}

class IOSFTPChannel: SFTPChannel {
    private var stateMachine: SFTPClientStateMachine
    private let eventLoop: EventLoop
    private var idAllocator: SFTPRequestIDAllocator

    // MARK: - Life Cycle

    fileprivate init(idAllocator: SFTPRequestIDAllocator,
                     eventLoop: EventLoop,
                     stateMachine: SFTPClientStateMachine) {
        self.stateMachine = stateMachine
        self.eventLoop = eventLoop
        self.idAllocator = idAllocator
    }

    // MARK: - SFTP

    func close() -> Future<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        trigger(.requestDisconnection(promise))
        return promise.futureResult
    }

    func openFile(_ file: SFTPMessage.OpenFile.Payload) -> Future<SFTPMessage.Handle> {
        allocateRequestID().flatMap { id in
            self.send(.openFile(.init(requestId: id, payload: file)))
        }
        .flatMapThrowing { response in
            switch response {
            case .handle(let handle):
                return handle
            default:
                throw SFTPError.invalidResponse
            }
        }
    }

    func closeFile(_ file: SFTPFileHandle) -> Future<SFTPMessage.Status> {
        allocateRequestID().flatMap { id in
            self.send(.closeFile(.init(requestId: id, handle: file)))
        }
        .flatMapThrowing { response in
            try self.mapStatus(response)
        }
    }

    func readFile(_ file: SFTPMessage.ReadFile.Payload) -> Future<SFTPMessage.ReadFile.Response> {
        allocateRequestID().flatMap { id in
            self.send(.read(.init(requestId: id, payload: file)))
        }
        .flatMapThrowing { response in
            switch response {
            case .data(let data):
                return .fileData(data)
            case .status(let status):
                switch status.payload.errorCode {
                case .eof, .ok:
                    return .status(status)
                default:
                    throw SFTPError.invalidResponse
                }
            default:
                throw SFTPError.invalidResponse
            }
        }
    }

    func writeFile(_ file: SFTPMessage.WriteFile.Payload) -> Future<SFTPMessage.Status> {
        allocateRequestID().flatMap { id in
            self.send(.write(.init(requestId: id, payload: file)))
        }
        .flatMapThrowing { response in
            try self.mapStatus(response)
        }
    }

    func mkdir(_ dir: SFTPMessage.MkDir.Payload) -> Future<SFTPMessage.Status> {
        allocateRequestID().flatMap { id in
            self.send(.mkdir(.init(requestId: id, payload: dir)))
        }
        .flatMapThrowing { response in
            try self.mapStatus(response)
        }
    }

    func rmdir(path: String) -> Future<SFTPMessage.Status> {
        allocateRequestID().flatMap { id in
            self.send(.rmdir(.init(requestId: id, filePath: path)))
        }
        .flatMapThrowing { response in
            try self.mapStatus(response)
        }
    }

    func rmFile(path: String) -> Future<SFTPMessage.Status> {
        allocateRequestID().flatMap { id in
            self.send(.remove(.init(requestId: id, filename: path)))
        }
        .flatMapThrowing { response in
            try self.mapStatus(response)
        }
    }

    func readDir(_ handle: SFTPFileHandle) -> Future<SFTPMessage.ReadDir.Response> {
        allocateRequestID().flatMap { id in
            self.send(.readdir(.init(requestId: id, handle: handle)))
        }
        .flatMapThrowing { response in
            switch response {
            case .status(let status):
                switch status.payload.errorCode {
                case .eof, .ok:
                    return .status(status)
                default:
                    throw SFTPError.invalidResponse
                }
            case .name(let name):
                return .name(name)
            default:
                throw SFTPError.invalidResponse
            }
        }
    }

    func openDir(path: String) -> Future<SFTPMessage.Handle> {
        allocateRequestID().flatMap { id in
            self.send(.opendir(.init(requestId: id, path: path)))
        }
        .flatMapThrowing { response in
            switch response {
            case .handle(let handle):
                return handle
            default:
                throw SFTPError.invalidResponse
            }
        }
    }

    func realpath(path: String) -> Future<SFTPMessage.Name> {
        allocateRequestID().flatMap { id in
            self.send(.realpath(.init(requestId: id, path: path)))
        }
        .flatMapThrowing { response in
            switch response {
            case .name(let name):
                return name
            default:
                throw SFTPError.invalidResponse
            }
        }
    }

    func stat(path: String) -> Future<SFTPMessage.Attributes> {
        allocateRequestID().flatMap { id in
            self.send(.stat(.init(requestId: id, path: path)))
        }
        .flatMapThrowing { response in
            switch response {
            case .attributes(let attributes):
                return attributes
            default:
                throw SFTPError.invalidResponse
            }
        }
    }

    func rename(_ payload: SFTPMessage.Rename.Payload) -> Future<SFTPMessage.Status> {
        allocateRequestID().flatMap { id in
            self.send(.rename(.init(requestId: id, payload: payload)))
        }
        .flatMapThrowing { response in
            try self.mapStatus(response)
        }
    }

    // MARK: - Private

    private func allocateRequestID() -> Future<SFTPRequestID> {
        eventLoop.submit {
            self.idAllocator.allocateRequestID()
        }
    }

    private func send(_ message: SFTPMessage) -> Future<SFTPResponse> {
        let promise = eventLoop.makePromise(of: SFTPResponse.self)
        trigger(.requestMessage(message, promise))
        return promise.futureResult
    }

    private func mapStatus(_ response: SFTPResponse) throws -> SFTPMessage.Status {
        switch response {
        case .status(let status):
            switch status.payload.errorCode {
            case .eof, .ok:
                return status
            default:
                throw SFTPError.invalidResponse
            }
        default:
            throw SFTPError.invalidResponse
        }
    }

    fileprivate func trigger(_ event: SFTPClientEvent) {
        eventLoop.execute {
            let action = self.stateMachine.handle(event)
            self.handle(action)
        }
    }

    private func handle(_ action: SFTPClientAction) {
        switch action {
        case .emitMessage(let message, let channel):
            channel
                .writeAndFlush(message)
                .whenComplete { [weak self] result in
                    switch result {
                    case .success:
                        self?.trigger(.messageSent(message))
                    case .failure(let error):
                        self?.trigger(.messageFailed(message, error))
                    }
                }
        case .disconnect(let channel):
            // SFTPChannel already listens `close` event in `launch`
            _ = channel
                .close()
        case .none:
            break
        }
    }
}

import NIOSSH

final class SFTPSession: SSHSession {
    struct Configuration {
        let updateQueue: DispatchQueue
    }

    let client: SFTPClient

    init(client: SFTPClient) {
        self.client = client
    }

    static func launch(on channel: Channel,
                       promise: Promise<SFTPSession>,
                       configuration: Configuration) {
        let deserializeHandler = ByteToMessageHandler(SFTPMessageParser())
        let serializeHandler = MessageToByteHandler(SFTPMessageSerializer())
        let sftpChannel = IOSFTPChannel(
            idAllocator: MonotonicRequestIDAllocator(start: 0),
            eventLoop: channel.eventLoop,
            stateMachine: SFTPClientStateMachine(channel: channel)
        )
        let sftpInboundHandler = SFTPClientInboundHandler { [weak sftpChannel] response in
            sftpChannel?.trigger(.inboundMessage(response))
        }
        let startPromise = channel.eventLoop.makePromise(
            of: Void.self
        )
        channel.closeFuture.whenComplete { [weak sftpChannel] _ in
            sftpChannel?.trigger(.disconnected)
        }
        let openSubsystem = channel.eventLoop.makePromise(of: Void.self)
        channel.triggerUserOutboundEvent(
            SSHChannelRequestEvent.SubsystemRequest(
                subsystem: "sftp",
                wantReply: true
            ),
            promise: openSubsystem
        )
        let result = openSubsystem
            .futureResult
            .map { channel }
            .flatMap { channel in
                channel.pipeline.addHandlers(
                    [
                        SSHChannelDataUnwrapper(),
                        SSHOutboundChannelDataWrapper(),
                    ]
                )
                .map { channel }
            }
            .flatMap { channel in
                channel.pipeline.addHandlers(
                    deserializeHandler,
                    serializeHandler,
                    sftpInboundHandler,
                    NIOCloseOnErrorHandler()
                )
            }
            .flatMap {
                sftpChannel.trigger(.start(startPromise))
                return startPromise.futureResult.map { sftpChannel }
            }
            .map {
                SFTPSession(
                    client: SFTPClient(sftpChannel: $0, updateQueue: configuration.updateQueue)
                )
            }
        promise.completeWith(result)
    }
}
