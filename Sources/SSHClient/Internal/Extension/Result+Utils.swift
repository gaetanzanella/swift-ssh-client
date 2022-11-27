
import Foundation

extension Result {
    func mapThrowing<New>(_ block: (Success) throws -> New) -> Result<New, Error> {
        Result<New, Error> { try block(try get()) }
    }
}
