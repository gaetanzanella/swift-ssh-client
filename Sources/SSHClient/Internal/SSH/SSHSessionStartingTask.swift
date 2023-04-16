
import Foundation
import NIOCore
import NIOSSH

class SSHSessionStartingTask: SSHTask {
    private var stateMachine = SSHSessionStartingTaskStateMachine()

    let session: SSHSession
    let eventLoop: EventLoop

    init(session: SSHSession, eventLoop: EventLoop) {
        self.session = session
        self.eventLoop = eventLoop
    }

    func didEnd(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            _ = eventLoop.submit { [weak self] in
                self?.trigger(.ended)
            }
        case .failure:
            _ = eventLoop.submit { [weak self] in
                self?.trigger(.fail)
            }
        }
    }

    func didLaunchSession(_ channel: Channel) {
        _ = eventLoop.submit { [weak self] in
            self?.trigger(.launching(channel))
        }
    }

    func cancel() {
        _ = eventLoop.submit { [weak self] in
            self?.trigger(.cancelled)
        }
    }

    private func trigger(_ event: SSHSessionStartingTaskEvent) {
        let action = stateMachine.handle(event)
        handle(action)
    }

    private func handle(_ action: SSHSessionStartingTaskAction) {
        switch action {
        case .none:
            break
        case .end(let channel):
            _ = channel.close()
        }
    }
}

enum SSHSessionStartingTaskEvent {
    case cancelled
    case launching(Channel)
    case ended
    case fail
}

enum SSHSessionStartingTaskAction {
    case none
    case end(Channel)
}

struct SSHSessionStartingTaskStateMachine {
    enum State {
        case initialized
        case cancelled
        case launching(Channel)
        case cancelling(Channel)
        case ended
    }

    private var state: State = .initialized

    mutating func handle(_ event: SSHSessionStartingTaskEvent) -> SSHSessionStartingTaskAction {
        switch state {
        case .initialized:
            switch event {
            case .cancelled:
                state = .cancelled
                return .none
            case .launching(let channel):
                state = .launching(channel)
                return .none
            case .ended:
                assertionFailure("Invalid transition")
                return .none
            case .fail:
                state = .ended
                return .none
            }
        case .cancelled:
            switch event {
            case .cancelled:
                return .none
            case .launching(let channel):
                state = .cancelling(channel)
                return .end(channel)
            case .ended:
                state = .ended
                return .none
            case .fail:
                state = .ended
                return .none
            }
        case .launching(let channel):
            switch event {
            case .cancelled:
                state = .cancelling(channel)
                return .end(channel)
            case .ended:
                state = .ended
                return .none
            case .launching:
                assertionFailure("Invalid transition")
                return .none
            case .fail:
                state = .ended
                return .none
            }
        case .cancelling:
            switch event {
            case .cancelled:
                return .none
            case .launching:
                assertionFailure("Invalid transition")
                return .none
            case .ended:
                state = .ended
                return .none
            case .fail:
                state = .ended
                return .none
            }
        case .ended:
            switch event {
            case .cancelled:
                // we ignore the cancellation if the task already ended.
                return .none
            case .launching:
                assertionFailure("Invalid transition")
                return .none
            case .ended:
                assertionFailure("Invalid transition")
                return .none
            case .fail:
                assertionFailure("Invalid transition")
                return .none
            }
        }
    }
}
