
import Foundation
import NIOCore
import NIOSSH

protocol SSHSession {

    associatedtype Configuration

    static func launch(on channel: Channel,
                       promise: Promise<Self>,
                       configuration: Configuration)
}
