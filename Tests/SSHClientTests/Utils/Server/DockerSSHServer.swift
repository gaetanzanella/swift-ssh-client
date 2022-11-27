
import Foundation

class DockerSSHServer: SSHServer {
    var username: String {
        "username"
    }

    var password: String {
        "password"
    }

    var host: String {
        "localhost"
    }

    var port: UInt16 {
        2223
    }

    var timeBeforeAuthentication: TimeInterval = 0.0

    var hasActiveChild: Bool {
        false
    }

    func end() {
        // can not be ended :(
    }

    func run() throws {
        // already running
    }
}
