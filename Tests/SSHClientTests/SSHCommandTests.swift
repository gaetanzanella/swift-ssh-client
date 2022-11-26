
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
                XCTAssertEqual(success.exitStatus, 0)
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
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
                XCTAssertNotEqual(success.exitStatus, 0)
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
    }

    func testStreaming() {
        let connection = launchConnection()
        let exp = XCTestExpectation()
        let statusExp = XCTestExpectation()
        let chunkExp = XCTestExpectation()
        connection.stream(
            "ls\n",
            withTimeout: 1.0
        ) { chunk in
            print("🔥 CHUNK")
            XCTAssertEqual(chunk.channel, .standard)
            XCTAssertEqual(chunk.data, "logs\nssh_host_keys\nsshd.pid\n".data(using: .utf8)!)
            chunkExp.fulfill()
        } onStatus: { status in
            print("🔥 Status")
            XCTAssertEqual(status.exitStatus, 0)
            statusExp.fulfill()
        } completion: { result in
            print("🔥 Completion")
            XCTAssertTrue(result.isSuccess)
            exp.fulfill()
        }
        wait(for: [exp, chunkExp, statusExp], timeout: 3)
    }

    func testWrongCommandStreaming() {
        let connection = launchConnection()
        let exp = XCTestExpectation()
        let statusExp = XCTestExpectation()
        let chunkExp = XCTestExpectation()
        connection.stream(
            "wrong-command\n",
            withTimeout: 1.0
        ) { chunk in
            XCTAssertEqual(chunk.channel, .error)
            XCTAssertEqual(chunk.data, "bash: line 1: wrong-command: command not found\n".data(using: .utf8)!)
            chunkExp.fulfill()
        } onStatus: { status in
            XCTAssertNotEqual(status.exitStatus, 0)
            statusExp.fulfill()
        } completion: { result in
            XCTAssertTrue(result.isSuccess)
            exp.fulfill()
        }
        wait(for: [exp, chunkExp, statusExp], timeout: 3)
    }

    func testCapture() {
        let connection = launchConnection()
        let exp = XCTestExpectation()
        connection.capture(
            "ls\n",
            withTimeout: 1.0
        ) { result in
            switch result {
            case .success(let success):
                XCTAssertEqual(success.status?.exitStatus, 0)
                XCTAssertEqual(success.standardOutput, "logs\nssh_host_keys\nsshd.pid\n".data(using: .utf8)!)
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
    }

    func testWrongCommandCapture() {
        let connection = launchConnection()
        let exp = XCTestExpectation()
        connection.capture(
            "wrong-command\n",
            withTimeout: 1.0
        ) { result in
            switch result {
            case .success(let success):
                XCTAssertNotEqual(success.status?.exitStatus, 0)
                XCTAssertEqual(success.errorOutput, "bash: line 1: wrong-command: command not found\n".data(using: .utf8)!)
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
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
