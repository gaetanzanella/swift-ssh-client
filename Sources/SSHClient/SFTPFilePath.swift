
import Foundation

public struct SFTPFilePath: Sendable, Hashable {
    private let stringValue: String

    public init(_ string: String) {
        stringValue = string
    }

    // MARK: - Public

    public var string: String {
        stringValue
    }

    // MARK: - Internal

    func encode() -> String {
        stringValue
    }
}

extension SFTPFilePath: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
