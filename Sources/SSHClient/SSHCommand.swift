
import Foundation

public struct SSHCommandStatus: Sendable, Hashable {
    public let exitStatus: Int
}

public enum SSHCommandResponseChunk: Sendable, Hashable {
    case chunk(SSHCommandChunk)
    case status(SSHCommandStatus)
}

public struct SSHCommandChunk: Sendable, Hashable {
    public enum Channel: Sendable, Hashable {
        case standard
        case error
    }

    public let channel: Channel
    public let data: Data
}

public struct SSHCommand: Sendable, Hashable {
    public let command: String

    public init(_ command: String) {
        self.command = command
    }
}

public struct SSHCommandResponse: Sendable {
    public let command: SSHCommand
    public let status: SSHCommandStatus
    public let standardOutput: Data?
    public let errorOutput: Data?
}

extension SSHCommand: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
