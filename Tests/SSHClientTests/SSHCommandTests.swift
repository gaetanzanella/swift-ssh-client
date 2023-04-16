
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

    func testCommandImmediateCancellation() {
        let connection = launchConnection()
        let exp = XCTestExpectation()
        let task = connection.execute("echo Hello\n") { result in
            XCTAssertTrue(result.isFailure)
            exp.fulfill()
        }
        task.cancel()
        wait(for: [exp], timeout: 3)
    }

    func testCommandDelayedCancellation() {
        let connection = launchConnection()
        let exp = XCTestExpectation()
        var standardOutput = Data()
        var chunkCount = 0
        var task: SSHTask?
        task = connection.execute(
            "yes \"long\" | head -n 1000000\n",
            onChunk: { chunk in
                standardOutput.append(chunk.data)
                chunkCount += 1
                if chunkCount == 5 {
                    task?.cancel()
                }
            },
            onStatus: { _ in },
            completion: { result in
                XCTAssertTrue(result.isSuccess)
                switch result {
                case .success:
                    // 5000000 = successful output size
                    XCTAssertTrue(standardOutput.count < 5000000)
                    XCTAssertTrue(standardOutput.count > 100)
                case .failure:
                    break
                }
                exp.fulfill()
            }
        )
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
