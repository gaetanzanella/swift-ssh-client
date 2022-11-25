import Foundation
import NIO

enum SSHShellEvent {
    case requestStart(Channel, Promise<Void>)
    case requestWrite(Data, Promise<Void>)
    case requestClosing(Promise<Void>)
    case started
    case read(Data)
    case closed
}

enum SSHShellAction {
    case write(Data, Channel, Promise<Void>)
    case close(Channel)
    case start(Channel)
    case dataAvailable(Data)
    case callPromise(Promise<Void>, Result<Void, Error>)
    case none
}

struct SSHShellStateMachine {
    enum InternalState {
        case idle
        case starting(Channel, Promise<Void>)
        case ready(Channel)
        case closing(Promise<Void>)
        case failed(Error)
        case closed
    }

    private var internalState: InternalState

    var state: SSHShell.State {
        switch internalState {
        case .idle:
            return .idle
        case .starting:
            return .idle
        case .ready, .closing:
            return .ready
        case .failed(let error):
            return .failed((error as? SSHShellError) ?? .unknown)
        case .closed:
            return .closed
        }
    }

    // MARK: - Life Cycle

    init() {
        internalState = .idle
    }

    // MARK: - Public

    mutating func handle(_ event: SSHShellEvent) -> SSHShellAction {
        switch internalState {
        case .idle:
            switch event {
            case .requestStart(let channel, let promise):
                internalState = .starting(channel, promise)
                return .start(channel)
            case .requestWrite(_, let promise):
                return .callPromise(promise, .failure(SSHShellError.requireConnection))
            case .requestClosing(let promise):
                return .callPromise(promise, .failure(SSHShellError.requireConnection))
            case .started, .read, .closed:
                assertionFailure("Invalida transition")
                return .none
            }
        case .starting(let channel, let promise):
            switch event {
            case .started:
                internalState = .ready(channel)
                return .callPromise(promise, .success(()))
            case .requestStart(_, let promise):
                return .callPromise(promise, .failure(SSHShellError.requireConnection))
            case .requestWrite(_, let promise):
                return .callPromise(promise, .failure(SSHShellError.requireConnection))
            case .requestClosing(let promise):
                internalState = .closing(promise)
                return .close(channel)
            case .closed:
                internalState = .failed(SSHShellError.unknown)
                return .callPromise(promise, .failure(SSHShellError.unknown))
            case .read:
                return .none
            }
        case .ready(let channel):
            switch event {
            case .requestStart(_, let promise):
                return .callPromise(promise, .success(()))
            case .requestWrite(let data, let promise):
                return .write(data, channel, promise)
            case .requestClosing(let promise):
                internalState = .closing(promise)
                return .close(channel)
            case .started:
                assertionFailure("Invalid transition")
                return .none
            case .read(let data):
                return .dataAvailable(data)
            case .closed:
                internalState = .failed(SSHShellError.unknown)
                return .none
            }
        case .closing(let closingPromise):
            switch event {
            case .requestStart(_, let promise):
                return .callPromise(promise, .failure(SSHShellError.requireConnection))
            case .requestWrite(_, let promise):
                return .callPromise(promise, .failure(SSHShellError.requireConnection))
            case .requestClosing(let promise):
                promise.completeWith(closingPromise.futureResult)
                return .none
            case .started:
                assertionFailure("Invalid transition")
                return .none
            case .read:
                return .none
            case .closed:
                internalState = .closed
                return .callPromise(closingPromise, .success(()))
            }
        case .failed(let error):
            switch event {
            case .requestStart(_, let promise):
                return .callPromise(promise, .failure(error))
            case .requestWrite(_, let promise):
                return .callPromise(promise, .failure(error))
            case .requestClosing(let promise):
                // already closed
                return .callPromise(promise, .success(()))
            case .started:
                assertionFailure("Invalid transition")
                return .none
            case .read:
                assertionFailure("Invalid transition")
                return .none
            case .closed:
                assertionFailure("Invalid transition")
                return .none
            }
        case .closed:
            switch event {
            case .requestStart(_, let promise):
                return .callPromise(promise, .failure(SSHShellError.requireConnection))
            case .requestWrite(_, let promise):
                return .callPromise(promise, .failure(SSHShellError.requireConnection))
            case .requestClosing(let promise):
                // already closed
                return .callPromise(promise, .success(()))
            case .started:
                assertionFailure("Invalid transition")
                return .none
            case .read:
                assertionFailure("Invalid transition")
                return .none
            case .closed:
                assertionFailure("Invalid transition")
                return .none
            }
        }
    }
}
