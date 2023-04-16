
import Foundation
import NIOCore
import NIOSSH

struct SSHSessionContext {
    let channel: Channel
    let promise: Promise<Void>
}

protocol SSHSession {
    func start(in context: SSHSessionContext)
}
