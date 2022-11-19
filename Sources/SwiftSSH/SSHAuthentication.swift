
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

    public init(username: String, method: Method, hostKeyValidation: HostKeyValidation) {
        self.username = username
        self.method = method
        self.hostKeyValidation = hostKeyValidation
    }
}

import NIOSSH

extension SSHAuthentication {

    public struct Method {

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

extension SSHAuthentication {

    public struct HostKeyValidation {

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
