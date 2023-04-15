import Foundation
import NIO
import NIOSSH

public enum SSHShellError: Error {
    case requireConnection
    case unknown
}

public class SSHShell: @unchecked Sendable, SSHSession {
    enum State: Equatable {
        case idle
        case ready
        case closed
        case failed(SSHShellError)
    }

    private let ioShell: IOSSHShell
    private let updateQueue: DispatchQueue

    private var readListeners = BlockObserverHolder<Data>()
    private var closeListeners = BlockObserverHolder<SSHShellError?>()

    // For testing purpose.
    // We expose a simple `closeHandler` instead of the state as the starting is
    // entirely managed by `SSHConnection` and a `SSHShell` can not restart.
    var state: State {
        ioShell.state
    }

    var stateUpdateHandler: ((State) -> Void)?

    // MARK: - Life Cycle

    init(ioShell: IOSSHShell,
         updateQueue: DispatchQueue) {
        self.ioShell = ioShell
        self.updateQueue = updateQueue
        setupIOShell()
    }

    public var readHandler: ((Data) -> Void)? {
        set {
            readListeners.update(newValue, token: .publicAPI())
        }
        get {
            readListeners.observer(for: .publicAPI())
        }
    }

    public var closeHandler: ((SSHShellError?) -> Void)? {
        set {
            closeListeners.update(newValue, token: .publicAPI())
        }
        get {
            closeListeners.observer(for: .publicAPI())
        }
    }

    // MARK: - SSHSession

    func start(in context: SSHSessionContext) {
        ioShell.start(in: context)
    }

    public func cancel() {
        _ = ioShell.close()
    }

    // MARK: - Public

    public func write(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        ioShell.write(data).whenComplete(on: updateQueue, completion)
    }

    public func close(completion: @escaping (Result<Void, Error>) -> Void) {
        ioShell.close().whenComplete(on: updateQueue, completion)
    }

    // MARK: - Internal

    func addReadListener(_ block: @escaping (Data) -> Void) -> ObserverToken {
        readListeners.add(block)
    }

    func removeReadListener(_ uuid: ObserverToken) {
        readListeners.removeObserver(uuid)
    }

    func addCloseListener(_ block: @escaping (SSHShellError?) -> Void) -> ObserverToken {
        closeListeners.add(block)
    }

    func removeCloseListener(_ uuid: ObserverToken) {
        closeListeners.removeObserver(uuid)
    }

    // MARK: - Private

    private func setupIOShell() {
        ioShell.readHandler = { [weak self] data in
            self?.updateQueue.async {
                self?.readListeners.call(with: data)
            }
        }
        ioShell.stateUpdateHandler = { [weak self] state in
            self?.updateQueue.async {
                self?.stateUpdateHandler?(state)
                switch state {
                case .idle:
                    break
                case .ready:
                    break
                case .closed:
                    self?.closeListeners.call(with: nil)
                case .failed(let error):
                    self?.closeListeners.call(with: error)
                }
            }
        }
    }
}
