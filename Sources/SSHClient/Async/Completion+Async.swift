
import Foundation

func withCheckedResultContinuation<T>(_ operation: (_ completion: @escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        operation { result in
            switch result {
            case .success(let success):
                continuation.resume(returning: success)
            case .failure(let failure):
                continuation.resume(throwing: failure)
            }
        }
    }
}

func withTaskCancellationHandler<T>(_ operation: (_ completion: @escaping (Result<T, Error>) -> Void) -> SSHTask) async throws -> T {
    let action = TaskAction()
    return try await withTaskCancellationHandler(operation: {
        try await withCheckedResultContinuation { completion in
            let task = operation(completion)
            action.setTask(task)
        }
    }, onCancel: {
        action.cancel()
    })
}

// inspired by https://github.com/swift-server/async-http-client/blob/main/Sources/AsyncHTTPClient/AsyncAwait/HTTPClient%2Bexecute.swift#L155
actor TaskAction {

    enum State {
        case initialized
        case task(SSHTask)
        case ended
    }

    private var state: State = .initialized

    nonisolated func setTask(_ task: SSHTask) {
        Task {
            await _setTask(task)
        }
    }

    nonisolated func cancel() {
        Task {
            await _cancel()
        }
    }

    private func _setTask(_ task: SSHTask) {
        state = .task(task)
    }

    private func _cancel() {
        switch state {
        case .ended, .initialized:
            break
        case let .task(task):
            task.cancel()
        }
    }
}
