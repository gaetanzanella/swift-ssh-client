
import Foundation

public extension SSHConnection {
    typealias AsyncSSHCommandResponse = AsyncThrowingStream<SSHCommandResponseChunk, Error>

    func start(withTimeout timeout: TimeInterval? = nil) async throws {
        try await withCheckedResultContinuation { completion in
            start(withTimeout: timeout, completion: completion)
        }
    }

    func cancel() async {
        await withCheckedContinuation { continuation in
            cancel(completion: continuation.resume)
        }
    }

    func execute(_ command: SSHCommand,
                 withTimeout timeout: TimeInterval? = nil) async throws -> SSHCommandResponse {
        try await withTaskCancellationHandler { completion in
            execute(command, withTimeout: timeout, completion: completion)
        }
    }

    func requestShell(withTimeout timeout: TimeInterval? = nil) async throws -> SSHShell {
        try await withTaskCancellationHandler { completion in
            requestShell(withTimeout: timeout, completion: completion)
        }
    }

    func requestSFTPClient(withTimeout timeout: TimeInterval? = nil) async throws -> SFTPClient {
        try await withTaskCancellationHandler { completion in
            requestSFTPClient(withTimeout: timeout, completion: completion)
        }
    }

    func stream(_ command: SSHCommand,
                withTimeout timeout: TimeInterval? = nil) async throws -> AsyncSSHCommandResponse {
        try await withTaskCancellationHandler { completion in
            enum State {
                case initializing
                case streaming(AsyncSSHCommandResponse.Continuation)
            }
            let action = TaskAction()
            // Each callback are executed on the internal serial ssh connection queue.
            // This is thread safe to modify the state inside them.
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
                case .streaming(let continuation):
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
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }
                }
            }
            action.setTask(resultTask)
            return resultTask
        }
    }
}
