
import Foundation

public struct SSHAuthentication {
    public struct Password {
        public var password: String

        public init(_ password: String) {
            self.password = password
        }
    }

    public let username: String
    public let method: Method
    public let hostKeyValidation: HostKeyValidation
    public var transportProtection: TransportProtection

    public init(username: String,
                method: Method,
                hostKeyValidation: HostKeyValidation) {
        self.username = username
        self.method = method
        self.hostKeyValidation = hostKeyValidation
        transportProtection = TransportProtection()
    }
}

import NIOSSH

public extension SSHAuthentication {
    struct Method {
        enum Implementation {
            case none
            case password(Password)
            case custom(NIOSSHClientUserAuthenticationDelegate)
        }

        let implementation: Implementation

        public static func password(_ password: Password) -> Method {
            .init(implementation: .password(password))
        }

        public static func none() -> Method {
            .init(implementation: .none)
        }

        public static func custom(_ delegate: NIOSSHClientUserAuthenticationDelegate) -> Method {
            .init(implementation: .custom(delegate))
        }
    }
}

public extension SSHAuthentication {
    struct HostKeyValidation {
        enum Implementation {
            case acceptAll
            case custom(NIOSSHClientServerAuthenticationDelegate)
        }

        let implementation: Implementation

        public static func acceptAll() -> HostKeyValidation {
            .init(implementation: .acceptAll)
        }

        public static func custom(_ delegate: NIOSSHClientServerAuthenticationDelegate) -> HostKeyValidation {
            .init(implementation: .custom(delegate))
        }
    }
}

public extension SSHAuthentication {
    struct TransportProtection {
        public enum Scheme {
            case bundled
            case aes128CTR
            case custom(NIOSSHTransportProtection.Type)
        }

        public var schemes: [Scheme]

        public init() {
            schemes = [.bundled]
        }
    }
}
