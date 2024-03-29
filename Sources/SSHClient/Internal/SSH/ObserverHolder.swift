
import Foundation

struct ObserverToken: Hashable {
    private enum Content: Hashable {
        case id(UUID)
        case publicAPI
    }

    private var content: Content

    init() {
        content = .id(UUID())
    }

    private init(content: Content) {
        self.content = content
    }

    static func publicAPI() -> ObserverToken {
        ObserverToken(content: .publicAPI)
    }
}

class BlockObserverHolder<Value> {
    typealias Observer = (Value) -> Void

    private var observers: [ObserverToken: Observer] = [:]
    private let lock = NSLock()

    func call(with value: Value) {
        lock.withLock {
            observers
        }
        .forEach { $1(value) }
    }

    func observer(for token: ObserverToken) -> (Observer)? {
        observers[token]
    }

    func add(_ block: Observer?, for token: ObserverToken) {
        if let block = block {
            lock.withLock {
                observers[token] = block
            }
        } else {
            removeObserver(token)
        }
    }

    @discardableResult
    func add(_ block: @escaping Observer) -> ObserverToken {
        let token = ObserverToken()
        add(block, for: token)
        return token
    }

    func removeObserver(_ token: ObserverToken) {
        _ = lock.withLock {
            observers.removeValue(forKey: token)
        }
    }
}
