
import Foundation

extension SSHConnection {

    public typealias AsyncSSHCommandResponse = AsyncThrowingStream<SSHCommandResponseChunk, Error>

    public func start(withTimeout timeout: TimeInterval? = nil) async throws {
        try await withCheckedResultContinuation { completion in
            start(withTimeout: timeout, completion: completion)
        }
    }

    public func cancel() async {
        return await withCheckedContinuation { continuation in
            cancel(completion: continuation.resume)
        }
    }

    public func execute(_ command: SSHCommand,
                        withTimeout timeout: TimeInterval? = nil) async throws -> SSHCommandResponse {
        return try await withTaskCancellationHandler { completion in
            execute(command, withTimeout: timeout, completion: completion)
        }
    }

    public func stream(_ command: SSHCommand,
                       withTimeout timeout: TimeInterval? = nil) async throws -> AsyncSSHCommandResponse {
        return try await withTaskCancellationHandler { completion in
            enum State {
                case initializing
                case streaming(AsyncSSHCommandResponse.Continuation)
            }
            let action = TaskAction()
            // Each callback are executed on the internal serial ssh connection queue.
            // This is thread safe to modify the state inside then.
            var state: State = .initializing
            let stream = { (responseChunk: SSHCommandResponseChunk) in
                switch state {
                case .initializing:
                    let response = AsyncSSHCommandResponse { continuation in
                        state = .streaming(continuation)
                        continuation.onTermination = { _ in
                            action.cancel()
                        }
                        continuation.yield(responseChunk)
                    }
                    completion(.success(response))
                case let .streaming(continuation):
                    continuation.yield(responseChunk)
                }
            }
            let resultTask = execute(
                command,
                withTimeout: timeout
            ) { chunk in
                stream(.chunk(chunk))
            } onStatus: { st in
                stream(.status(st))
            } completion: { result in
                switch state {
                case .initializing:
                    completion(.failure(SSHConnectionError.unknown))
                case .streaming(let continuation):
                    switch result {
                    case .success:
                        continuation.finish()
                    case let .failure(error):
                        continuation.finish(throwing: error)
                    }
                }
            }
            action.setTask(resultTask)
            return resultTask
        }
    }
}
