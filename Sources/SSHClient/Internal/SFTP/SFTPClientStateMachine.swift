import Foundation
import NIO

enum SFTPClientEvent {
    case start(Channel, Promise<Void>)
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
    case callPromise(Promise<Void>, Result<Void, Error>)
    case callResponsePromise(Promise<SFTPResponse>, Result<SFTPResponse, Error>)
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
        case idle
        case sentVersion(Channel, Promise<Void>)
        case ready(Channel, SFTPInflightRequestList)
        case disconnecting(Channel, Promise<Void>, Error?)
        case failed(Error)
        case disconnected
    }

    private var internalState: InternalState

    var state: SFTPClient.State {
        switch internalState {
        case .idle:
            return .idle
        case .sentVersion:
            return .idle
        case .ready:
            return .ready
        case .disconnecting:
            return .ready
        case .failed(let error):
            return .failed((error as? SFTPClientError) ?? .unknown)
        case .disconnected:
            return .closed
        }
    }

    // MARK: - Life Cycle

    init() {
        internalState = .idle
    }

    // MARK: - Public

    mutating func handle(_ event: SFTPClientEvent) -> SFTPClientAction {
        switch internalState {
        case .idle:
            switch event {
            case .start(let channel, let promise):
                internalState = .sentVersion(channel, promise)
                return .emitMessage(
                    .initialize(.init(version: .v3)),
                    channel
                )
            case .requestMessage(_, let promise):
                return .callResponsePromise(promise, .failure(SFTPError.connectionClosed))
            case .requestDisconnection(let promise):
                return .callPromise(promise, .success(()))
            case .messageSent, .messageFailed, .disconnected, .inboundMessage:
                assertionFailure("Unexpected state")
                return .none
            }
        case .sentVersion(let channel, let startPromise):
            switch event {
            case .inboundMessage(let response):
                switch response {
                case .version(let version):
                    switch version.version {
                    case .unsupported:
                        let error = SFTPError.unsupportedVersion(version.version)
                        startPromise.fail(error)
                        internalState = .disconnecting(
                            channel,
                            startPromise,
                            SFTPError.unsupportedVersion(version.version)
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
            case .requestDisconnection(let endPromise):
                // we call the pending completions with an error once disconnected
                startPromise.completeWith(endPromise.futureResult.flatMapErrorThrowing { _ in
                    throw SFTPError.connectionClosed
                })
                internalState = .disconnecting(channel, endPromise, nil)
                return .disconnect(channel)
            case .disconnected:
                internalState = .failed(SFTPError.connectionClosed)
                return .callPromise(startPromise, .failure(SFTPError.connectionClosed))
            case .messageSent:
                return .none
            case .start, .requestMessage, .messageFailed:
                assertionFailure("Unexpected state")
                return .none
            }
        case .ready(let channel, var inflightRequests):
            switch event {
            case .inboundMessage(let response):
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
            case .requestMessage(let message, let promise):
                guard let id = message.requestID else {
                    return .callResponsePromise(promise, .failure(SFTPError.invalidResponse))
                }
                inflightRequests.set(
                    promise,
                    for: id
                )
                internalState = .ready(channel, inflightRequests)
                return .emitMessage(message, channel)
            case .messageSent:
                return .none
            case .messageFailed(let message, _):
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
            case .requestDisconnection(let promise):
                internalState = .disconnecting(channel, promise, nil)
                return .disconnect(channel)
            case .start:
                assertionFailure("Unexpected state")
                return .none
            }
        case .disconnecting(_, let promise, let error):
            switch event {
            case .disconnected:
                if let error {
                    internalState = .failed(error)
                } else {
                    internalState = .disconnected
                }
                return .callPromise(promise, .success(()))
            case .inboundMessage, .requestDisconnection, .start, .requestMessage, .messageSent, .messageFailed:
                assertionFailure("Unexpected state")
                return .none
            }
        case .disconnected, .failed:
            switch event {
            case .requestMessage(_, let promise):
                return .callResponsePromise(promise, .failure(SFTPError.invalidResponse))
            case .requestDisconnection(let promise):
                return .callPromise(promise, .success(()))
            case .start(_, let promise):
                return .callPromise(promise, .failure(SFTPError.invalidResponse))
            case .messageSent, .messageFailed:
                break
            case .inboundMessage, .disconnected:
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
