
import Foundation

struct SSHCommandInvocation {
    let command: SSHCommand
    let onChunk: ((SSHCommandChunk) -> Void)?
    let onStatus: ((SSHCommandStatus) -> Void)?
}
