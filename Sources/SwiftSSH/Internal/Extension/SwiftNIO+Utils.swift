
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
