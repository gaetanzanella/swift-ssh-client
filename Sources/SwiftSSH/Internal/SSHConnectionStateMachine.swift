
import Foundation
import NIO
import NIOSSH

typealias SSHCompletion<T> = (T) -> Void
typealias SSHCompletionList<T> = [SSHCompletion<T>]

enum SSHConnectionEvent {
    case requestDisconnection(SSHCompletion<Void>)
    case requestConnection(TimeInterval, SSHCompletion<Error?>)
    case connected(Channel)
    case authenticated(Channel)
    case disconnected
    case error(SSHConnection.ConnectionError)
}

enum SSHConnectionAction {
    case none
    case disconnect(Channel)
    case connect(TimeInterval)
    case callErrorCompletion(SSHCompletionList<Error?>, Error?)
    case callCompletion(SSHCompletionList<Void>)
}

struct SSHConnectionStateMachine {

    enum InternalState {
        case idle
        case ready(Channel)
        case connecting(SSHCompletionList<Error?>)
        case authenticating(Channel, SSHCompletionList<Error?>)
        case disconnecting(Channel, SSHCompletionList<Void>, error: SSHConnection.ConnectionError?)
        case failed(SSHConnection.ConnectionError)
    }

    private var internalState: InternalState = .idle

    var state: SSHConnection.State {
        switch internalState {
        case .idle:
            return .idle
        case let .failed(error):
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
        case let .disconnecting(channel, _, _):
            return channel
        case let .authenticating(channel, _):
            return channel
        case let .ready(channel):
            return channel
        }
    }

    mutating func handle(_ event: SSHConnectionEvent) -> SSHConnectionAction {
        switch internalState {
        case .idle:
            switch event {
            case let .requestDisconnection(completion):
                return .callCompletion([completion])
            case let .requestConnection(timeout, completion):
                self.internalState = .connecting([completion])
                return .connect(timeout)
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
            case let .requestDisconnection(completion):
                self.internalState = .disconnecting(channel, [completion], error: nil)
                return .disconnect(channel)
            case let .requestConnection(_, completion):
                return .callErrorCompletion([completion], nil)
            case let .error(error):
                internalState = .failed(error)
                return .none
            case .disconnected:
                internalState = .idle
                return .none
            case .authenticated:
                assertionFailure("Invalid transition")
                return .none
            case .connected(_):
                assertionFailure("Invalid transition")
                return .none
            }
        case .connecting(let sSHCompletionList):
            switch event {
            case let .connected(channel):
                self.internalState = .authenticating(channel, sSHCompletionList)
                // automatically done
                return .none
            case .requestDisconnection:
                // TODO
                return .none
            case let .error(error):
                internalState = .failed(error)
                return .callErrorCompletion(sSHCompletionList, error)
            case let .requestConnection(_, completion):
                self.internalState = .connecting(sSHCompletionList + [completion])
                return .none
            case .disconnected:
                assertionFailure("Invalid transition")
                return .none
            case .authenticated:
                assertionFailure("Invalid transition")
                return .none
            }
        case .authenticating(let channel, let sSHCompletionList):
            switch event {
            case let .authenticated(channel):
                internalState = .ready(channel)
                return .callErrorCompletion(sSHCompletionList, nil)
            case let .requestConnection(_, completion):
                self.internalState = .authenticating(channel, sSHCompletionList + [completion])
                return .none
            case let .requestDisconnection(completion):
                // we call the pending completions with an error once disconnected
                internalState = .disconnecting(
                    channel,
                    [completion] + sSHCompletionList.map({ completion -> SSHCompletion<Void> in
                        return { _ in
                            completion(SSHConnection.ConnectionError.unknown)
                        }
                    }),
                    error: nil
                )
                return .disconnect(channel)
            case let .error(error):
                internalState = .disconnecting(
                    channel,
                    sSHCompletionList.map({ completion -> SSHCompletion<Void> in
                        return { _ in
                            completion(error)
                        }
                    }),
                    error: error
                )
                return .disconnect(channel)
            case .connected:
                assertionFailure("Invalid transition")
                return .none
            case .disconnected:
                assertionFailure("Invalid transition")
                return .none
            }
        case .disconnecting(let channel, let sSHCompletionList, let error):
            switch event {
            case .disconnected:
                if let error = error {
                    internalState = .failed(error)
                } else {
                    internalState = .idle
                }
                return .callCompletion(sSHCompletionList)
            case let .error(error):
                internalState = .failed(error)
                return .callCompletion(sSHCompletionList)
            case let .requestDisconnection(completion):
                self.internalState = .disconnecting(channel, sSHCompletionList + [completion], error: error)
                return .callCompletion([completion])
            case let .requestConnection(_, completion):
                // TODO handle reconnection, for now we just cancel the connection
                return .callErrorCompletion([completion], SSHConnection.ConnectionError.unknown)
            case .authenticated:
                assertionFailure("Invalid transition")
                return .none
            case .connected:
                assertionFailure("Invalid transition")
                return .none
            }
        case .failed:
            switch event {
            case let .requestDisconnection(completion):
                return .callCompletion([completion])
            case let .requestConnection(timeout, completion):
                self.internalState = .connecting([completion])
                return .connect(timeout)
            case let .error(error):
                internalState = .failed(error)
                return .none
            case .disconnected:
                // Disconnection after failure
                return .none
            case .authenticated:
                assertionFailure("Invalid transition")
                return .none
            case .connected(_):
                assertionFailure("Invalid transition")
                return .none
            }
        }
    }
}
