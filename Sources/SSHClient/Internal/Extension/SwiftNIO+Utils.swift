
import Foundation

extension Future {
    func mapAsVoid() -> Future<Void> {
        map { _ in }
    }

    func whenComplete(on queue: DispatchQueue, _ callback: @escaping (Result<Value, Error>) -> Void) {
        whenComplete { result in
            queue.async {
                callback(result)
            }
        }
    }
}

extension Promise {
    func end<E: Error>(_ result: Result<Value, E>) {
        switch result {
        case .success(let success):
            succeed(success)
        case .failure(let failure):
            fail(failure)
        }
    }
}
