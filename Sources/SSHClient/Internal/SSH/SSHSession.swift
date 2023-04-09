
import Foundation
import NIOCore
import NIOSSH

struct SSHSessionContext {
    let channel: Channel
    let promise: Promise<Void>
}

protocol SSHSession: SSHTask {
    func start(in context: SSHSessionContext)
}
