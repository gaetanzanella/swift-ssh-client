import Foundation
import NIO
import NIOSSH

public class SSHShell: SSHSession {
    public enum State: Equatable {
        case idle
        case ready
        case closed
        case failed(SSHShellError)
    }

    private let ioShell: IOSSHShell
    private let updateQueue: DispatchQueue

    // MARK: - Life Cycle

    init(ioShell: IOSSHShell,
         updateQueue: DispatchQueue) {
        self.ioShell = ioShell
        self.updateQueue = updateQueue
    }

    public var readHandler: ((Data) -> Void)?
    public var stateUpdateHandler: ((State) -> Void)?

    // MARK: - SSHSession

    func start(in context: SSHSessionContext) {
        ioShell.start(in: context)
    }

    // MARK: - Public

    public func write(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        ioShell.write(data).whenComplete(on: updateQueue, completion)
    }

    public func close(completion: @escaping (Result<Void, Error>) -> Void) {
        ioShell.close().whenComplete(on: updateQueue, completion)
    }

    // MARK: - Private

    private func setupIOShell() {
        ioShell.readHandler = { [weak self] data in
            self?.updateQueue.async {
                self?.readHandler?(data)
            }
        }
        ioShell.stateUpdateHandler = { [weak self] state in
            self?.updateQueue.async {
                self?.stateUpdateHandler?(state)
            }
        }
    }
}
