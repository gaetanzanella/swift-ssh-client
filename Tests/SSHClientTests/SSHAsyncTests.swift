
import Foundation
import SSHClient
import XCTest

class SSHAsyncTests: XCTestCase {

    var sshServer: SSHServer!

    override func setUp() {
        sshServer = DockerSSHServer()
    }

    // MARK: - Connection

    func testCommandExecution() async throws {
        let connection = SSHConnection(
                host: sshServer.host,
                port: sshServer.port,
                authentication: sshServer.credentials
            )
        try await connection.start()
        await connection.cancel()
    }

    func testCommandStreaming() async throws {
        let connection = SSHConnection(
                host: sshServer.host,
                port: sshServer.port,
                authentication: sshServer.credentials
            )
        try await connection.start()
        let chunks = try await connection.stream("yes \"long text\" | head -n 1000000\n")
        var i = 0
        // TODO Add better testing
        for try await _ in chunks {
            i += 1
        }
        XCTAssertTrue(i > 10)
        await connection.cancel()
    }
}
