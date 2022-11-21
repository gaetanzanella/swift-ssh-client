import Foundation
import NIO

enum SFTPClientEvent {
    case start(Promise<Void>)
    case requestMessage(SFTPMessage, Promise<SFTPResponse>)
    case messageSent(SFTPMessage)
    case messageFailed(SFTPMessage, Error)
    case inboundMessage(SFTPResponse)
    case requestDisconnection(Promise<Void>)
    case disconnected
}

enum SFTPClientAction {
    case emitMessage(SFTPMessage, Channel)
    case disconnect(Channel)
    case none
}

private struct SFTPInflightRequestList {

    private var responses: [SFTPRequestID: Promise<SFTPResponse>] = [:]

    func promise(for id: SFTPRequestID) -> Promise<SFTPResponse>? {
        responses[id]
    }

    mutating func cleanPromise(for id: SFTPRequestID) {
        responses.removeValue(forKey: id)
    }

    mutating func set(_ request: Promise<SFTPResponse>,
                      for id: SFTPRequestID) {
        responses[id] = request
    }

    func allRequestIDs() -> [SFTPRequestID] {
        Array(responses.keys)
    }
}

struct SFTPClientStateMachine {

    private enum InternalState {
        case idle(Channel)
        case sentVersion(Channel, Promise<Void>)
        case ready(Channel, SFTPInflightRequestList)
        case disconnecting(Channel, Promise<Void>)
        case failed(Error)
        case disconnected
    }

    private var internalState: InternalState

    // MARK: - Life Cycle

    init(channel: Channel) {
        self.internalState = .idle(channel)
    }

    // MARK: - Public

    mutating func handle(_ event: SFTPClientEvent) -> SFTPClientAction {
        switch internalState {
        case let .idle(channel):
            switch event {
            case let .start(promise):
                self.internalState = .sentVersion(channel, promise)
                return .emitMessage(
                    .initialize(.init(version: .v3)),
                    channel
                )
            case .messageSent:
                return .none
            case .messageFailed:
                internalState = .failed(SFTPError.connectionClosed)
                return .disconnect(channel)
            case .disconnected:
                internalState = .failed(SFTPError.connectionClosed)
                return .none
            case let .requestDisconnection(promise):
                internalState = .disconnecting(channel, promise)
                return .disconnect(channel)
            case .inboundMessage, .requestMessage:
                assertionFailure("Unexpected state")
                return .none
            }
        case let .sentVersion(channel, startPromise):
            switch event {
            case let .inboundMessage(response):
                switch response {
                case let .version(version):
                    switch version.version {
                    case .unsupported:
                        let error = SFTPError.unsupportedVersion(version.version)
                        startPromise.fail(error)
                        internalState = .disconnecting(
                            channel,
                            startPromise
                        )
                        return .disconnect(channel)
                    case .v3:
                        startPromise.succeed(())
                        internalState = .ready(channel, SFTPInflightRequestList())
                        return .none
                    }
                default:
                    startPromise.fail(SFTPError.connectionClosed)
                    assertionFailure("Unexpected state")
                    return .none
                }
            case let .requestDisconnection(endPromise):
                startPromise.fail(SFTPError.connectionClosed)
                internalState = .disconnecting(channel, endPromise)
                return .disconnect(channel)
            case .disconnected:
                internalState = .failed(SFTPError.connectionClosed)
                startPromise.fail(SFTPError.connectionClosed)
                return .none
            case .messageSent:
                return .none
            case .start, .requestMessage, .messageFailed:
                assertionFailure("Unexpected state")
                return .none
            }
        case .ready(let channel, var inflightRequests):
            switch event {
            case let .inboundMessage(response):
                guard let id = response.id else {
                    assertionFailure("Unexpected state")
                    return .none
                }
                do {
                    try handle(
                        response,
                        forRequest: id,
                        inflightRequests: inflightRequests
                    )
                    return .none
                } catch {
                    return .disconnect(channel)
                }
            case let .requestMessage(message, promise):
                guard let id = message.requestID else {
                    promise.fail(SFTPError.invalidResponse)
                    return .none
                }
                inflightRequests.set(
                    promise,
                    for: id
                )
                internalState = .ready(channel, inflightRequests)
                return .emitMessage(message, channel)
            case .messageSent:
                return .none
            case let .messageFailed(message, _):
                guard let id = message.requestID else {
                    return .none
                }
                do {
                    // triggers error
                    try handle(nil, forRequest: id, inflightRequests: inflightRequests)
                    return .none
                } catch {
                    return .none
                }
            case .disconnected:
                internalState = .failed(SFTPError.connectionClosed)
                do {
                    // triggers error
                    try inflightRequests.allRequestIDs().forEach { id in
                        try handle(nil, forRequest: id, inflightRequests: inflightRequests)
                    }
                    return .none
                } catch {
                    return .none
                }
            case let .requestDisconnection(promise):
                internalState = .disconnecting(channel, promise)
                return .disconnect(channel)
            case .start:
                assertionFailure("Unexpected state")
                return .none
            }
        case let .disconnecting(_, promise):
            switch event {
            case .disconnected:
                internalState = .disconnected
                promise.succeed(())
                return .none
            case .inboundMessage, .requestDisconnection, .start, .requestMessage, .messageSent, .messageFailed:
                assertionFailure("Unexpected state")
                return .none
            }
        case .disconnected, .failed:
            switch event {
            case let .requestMessage(_, promise):
                promise.fail(SFTPError.invalidResponse)
            case let .requestDisconnection(promise):
                promise.succeed(())
            case let .start(promise):
                promise.fail(SFTPError.connectionClosed)
            case .inboundMessage, .messageSent, .messageFailed, .disconnected:
                assertionFailure("Unexpected state")
            }
            return .none
        }
    }

    // MARK: - Private

    private func handle(_ response: SFTPResponse?,
                        forRequest id: SFTPRequestID,
                        inflightRequests: SFTPInflightRequestList) throws {
        guard let promise = inflightRequests.promise(for: id) else {
            throw SFTPError.missingResponse
        }
        if let response = response {
            promise.succeed(response)
        } else {
            promise.fail(SFTPError.missingResponse)
        }
    }
}
