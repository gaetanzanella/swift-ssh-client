
import Foundation
@testable import SSHClient
import XCTest

class SSHCommandTests: XCTestCase {
    var sshServer: SSHServer!
    var connection: SSHConnection!

    override func setUp() {
        sshServer = DockerSSHServer()
        connection = SSHConnection(
            host: sshServer.host,
            port: sshServer.port,
            authentication: sshServer.credentials
        )
    }

    override func tearDown() {
        connection.cancel {}
    }

    // MARK: - Tests

    func testExecution() {
        let connection = launchConnection()
        let exp = XCTestExpectation()
        connection.execute(
            "ls\n",
            withTimeout: 1.0
        ) { result in
            switch result {
            case .success(let success):
                XCTAssertEqual(success.status.exitStatus, 0)
                XCTAssertEqual(success.standardOutput, "logs\nssh_host_keys\nsshd.pid\n".data(using: .utf8)!)
                XCTAssertNil(success.errorOutput)
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
    }

    func testWrongCommandExecution() {
        let connection = launchConnection()
        let exp = XCTestExpectation()
        connection.execute(
            "wrong-command\n",
            withTimeout: 1.0
        ) { result in
            switch result {
            case .success(let success):
                XCTAssertNotEqual(success.status.exitStatus, 0)
                XCTAssertEqual(success.errorOutput, "bash: line 1: wrong-command: command not found\n".data(using: .utf8)!)
                XCTAssertNil(success.standardOutput)
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
    }

    func testConnectionShutDown() {
        let connection = launchConnection()
        let exp = XCTestExpectation()
        connection.execute(
            "echo Hello\n",
            withTimeout: 1.0
        ) { result in
            XCTAssertTrue(result.isFailure)
            exp.fulfill()
        }
        connection.cancel {}
        wait(for: [exp], timeout: 3)
    }

    // MARK: - Private

    private func launchConnection() -> SSHConnection {
        let exp = XCTestExpectation()
        connection.start(withTimeout: 2) { result in
            XCTAssertTrue(result.isSuccess)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
        return connection
    }
}
