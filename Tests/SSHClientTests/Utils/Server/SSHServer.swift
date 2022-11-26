
import Crypto
import Dispatch
import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SSHClient

protocol SSHServer {
    var username: String { get }
    var password: String { get }
    var host: String { get }
    var port: UInt16 { get }

    var timeBeforeAuthentication: TimeInterval { get set }
    var hasActiveChild: Bool { get }
    func end()
    func run() throws
}

extension SSHServer {

    var credentials: SSHAuthentication {
        .init(
            username: username,
            method: .password(.init(password)),
            hostKeyValidation: .acceptAll()
        )
    }
}
