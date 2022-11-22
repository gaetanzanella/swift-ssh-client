
import Foundation
import NIO
import NIOSSH

enum SSHConnectionEvent {
    case requestDisconnection(Promise<Void>)
    case requestConnection(TimeInterval, Promise<Void>)
    case requestSession(SSHSession, TimeInterval, Promise<Void>)
    case connected(Channel)
    case authenticated(Channel)
    case disconnected
    case error(SSHConnectionError)
}

enum SSHConnectionAction {
    case none
    case disconnect(Channel)
    case requestSession(Channel, SSHSession, TimeInterval, Promise<Void>)
    case connect(TimeInterval)
    case callPromise(Promise<Void>, Result<Void, SSHConnectionError>)
}

struct SSHConnectionStateMachine {
    enum InternalState {
        case idle
        case ready(Channel)
        case connecting(Promise<Void>)
        case authenticating(Channel, Promise<Void>)
        case disconnecting(Channel, Promise<Void>, error: SSHConnectionError?)
        case failed(SSHConnectionError)
    }

    private var internalState: InternalState = .idle

    var state: SSHConnection.State {
        switch internalState {
        case .idle:
            return .idle
        case .failed(let error):
            return .failed(error)
        case .connecting, .authenticating:
            return .idle
        case .disconnecting:
            return .idle
        case .ready:
            return .ready
        }
    }

    var channel: Channel? {
        switch internalState {
        case .idle, .failed, .connecting:
            return nil
        case .disconnecting(let channel, _, _):
            return channel
        case .authenticating(let channel, _):
            return channel
        case .ready(let channel):
            return channel
        }
    }

    mutating func handle(_ event: SSHConnectionEvent) -> SSHConnectionAction {
        switch internalState {
        case .idle:
            switch event {
            case .requestDisconnection(let promise):
                return .callPromise(promise, .success(()))
            case .requestConnection(let timeout, let promise):
                internalState = .connecting(promise)
                return .connect(timeout)
            case .requestSession(_, _, let promise):
                return .callPromise(promise, .failure(.requireActiveConnection))
            case .error:
                // Should be an error due to a connection cancelling
                assertionFailure("Invalid transition")
                return .none
            case .connected, .authenticated, .disconnected:
                assertionFailure("Invalid transition")
                return .none
            }
        case .ready(let channel):
            switch event {
            case .requestDisconnection(let promise):
                internalState = .disconnecting(channel, promise, error: nil)
                return .disconnect(channel)
            case .requestConnection(_, let promise):
                return .callPromise(promise, .success(()))
            case .requestSession(let session, let timeout, let promise):
                return .requestSession(channel, session, timeout, promise)
            case .error(let error):
                internalState = .failed(error)
                return .none
            case .disconnected:
                internalState = .idle
                return .none
            case .authenticated:
                assertionFailure("Invalid transition")
                return .none
            case .connected:
                assertionFailure("Invalid transition")
                return .none
            }
        case .connecting(let promise):
            switch event {
            case .connected(let channel):
                internalState = .authenticating(channel, promise)
                // automatically done
                return .none
            case .requestDisconnection:
                // TODO:
                return .none
            case .requestSession(_, _, let promise):
                return .callPromise(promise, .failure(.requireActiveConnection))
            case .error(let error):
                internalState = .failed(error)
                return .callPromise(promise, .failure(error))
            case .requestConnection(_, let new):
                new.completeWith(promise.futureResult)
                return .none
            case .disconnected:
                assertionFailure("Invalid transition")
                return .none
            case .authenticated:
                assertionFailure("Invalid transition")
                return .none
            }
        case .authenticating(let channel, let promise):
            switch event {
            case .authenticated(let channel):
                internalState = .ready(channel)
                return .callPromise(promise, .success(()))
            case .requestConnection(_, let new):
                new.completeWith(promise.futureResult)
                return .none
            case .requestDisconnection(let new):
                // we call the pending completions with an error once disconnected
                promise.completeWith(
                    new.futureResult.flatMapThrowing { throw SSHConnectionError.unknown }
                )
                internalState = .disconnecting(
                    channel,
                    new,
                    error: nil
                )
                return .disconnect(channel)
            case .requestSession(_, _, let promise):
                return .callPromise(promise, .failure(.requireActiveConnection))
            case .error(let error):
                internalState = .disconnecting(
                    channel,
                    promise,
                    error: error
                )
                return .disconnect(channel)
            case .connected:
                assertionFailure("Invalid transition")
                return .none
            case .disconnected:
                internalState = .failed(SSHConnectionError.unknown)
                return .callPromise(promise, .failure(.unknown))
            }
        case .disconnecting(_, let promise, let error):
            switch event {
            case .disconnected:
                if let error = error {
                    internalState = .failed(error)
                    return .callPromise(promise, .failure(error))
                } else {
                    internalState = .idle
                    return .callPromise(promise, .success(()))
                }
            case .error(let error):
                internalState = .failed(error)
                return .callPromise(promise, .failure(error))
            case .requestSession(_, _, let promise):
                return .callPromise(promise, .failure(.requireActiveConnection))
            case .requestDisconnection(let new):
                new.completeWith(promise.futureResult)
                return .none
            case .requestConnection(_, let new):
                // TODO: handle reconnection, for now we just cancel the connection
                return .callPromise(new, .failure(.requireActiveConnection))
            case .authenticated:
                assertionFailure("Invalid transition")
                return .none
            case .connected:
                assertionFailure("Invalid transition")
                return .none
            }
        case .failed:
            switch event {
            case .requestDisconnection(let promise):
                return .callPromise(promise, .failure(.requireActiveConnection))
            case .requestConnection(let timeout, let promise):
                internalState = .connecting(promise)
                return .connect(timeout)
            case .requestSession(_, _, let promise):
                return .callPromise(promise, .failure(.requireActiveConnection))
            case .error(let error):
                internalState = .failed(error)
                return .none
            case .disconnected:
                // Disconnection after failure
                return .none
            case .authenticated:
                assertionFailure("Invalid transition")
                return .none
            case .connected:
                assertionFailure("Invalid transition")
                return .none
            }
        }
    }
}
