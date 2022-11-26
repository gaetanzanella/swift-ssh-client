
import Foundation

struct SSHCommandInvocation {
    let command: SSHCommand
    let wantsReply: Bool
    let onChunk: ((SSHCommandChunk) -> Void)?
    let onStatus: ((SSHCommandStatus) -> Void)?
}
