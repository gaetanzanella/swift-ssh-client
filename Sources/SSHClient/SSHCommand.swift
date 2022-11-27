
import Foundation

public struct SSHCommandStatus {
    public let exitStatus: Int
}

public struct SSHCommandChunk {
    public enum Channel {
        case standard
        case error
    }

    public let channel: Channel
    public let data: Data
}

public struct SSHCommand {
    public let command: String

    public init(_ command: String) {
        self.command = command
    }
}

public struct SSHCommandResponse {
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
