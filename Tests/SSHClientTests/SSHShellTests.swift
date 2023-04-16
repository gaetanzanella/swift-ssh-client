
import Foundation
@testable import SSHClient
import XCTest

class SSHShellTests: XCTestCase {
    var sftpServer: SSHServer!
    var connection: SSHConnection!

    override func setUp() {
        sftpServer = DockerSSHServer()
        connection = SSHConnection(
            host: sftpServer.host,
            port: sftpServer.port,
            authentication: sftpServer.credentials
        )
    }

    override func tearDown() {
        connection.cancel {}
    }

    // MARK: - Shell

    func testShellLaunch() throws {
        let shell = try launchShell()
        XCTAssertEqual(shell.states, [])
        XCTAssertEqual(shell.state, .ready)
    }

    func testCommand() throws {
        let shell = try launchShell()
        let exp = XCTestExpectation()
        shell.shell.write("pwd\n".data(using: .utf8)!) { result in
            XCTAssert(result.isSuccess)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        wait(timeout: 2)
        XCTAssertEqual(shell.data[0], "/config\n".data(using: .utf8))
    }

    func testClosing() throws {
        let shell = try launchShell()
        let exp = XCTestExpectation()
        shell.shell.close { result in
            XCTAssert(result.isSuccess)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(shell.states, [.closed])
        XCTAssertEqual(shell.state, .closed)
    }

    func testShellImmediateCancellation() throws {
        let connection = try launchConnection()
        let exp = XCTestExpectation()
        let task = connection.requestShell { result in
            XCTAssert(result.isFailure)
            exp.fulfill()
        }
        task.cancel()
        wait(for: [exp], timeout: 2)
    }

    func testShellDelayedCancellationShouldDoNothing() throws {
        let connection = try launchConnection()
        let exp = XCTestExpectation()
        var task: SSHTask?
        var shell: EmbeddedShell?
        task = connection.requestShell { result in
            shell = (try? result.get()).flatMap { EmbeddedShell(shell: $0) }
            task?.cancel()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        wait(timeout: 0.5)
        XCTAssertEqual(shell!.states, [])
    }

    // MARK: - Errors

    func testDisconnectionError() throws {
        let shell = try launchShell()
        XCTAssertEqual(shell.states, [])
        let exp = XCTestExpectation()
        connection.cancel {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(shell.states, [.failed(.unknown)])
    }

    func testTimeoutError() throws {
        let exp = XCTestExpectation()
        connection.start(withTimeout: 2) { result in
            XCTAssertTrue(result.isSuccess)
            self.connection.requestShell(withTimeout: 0.2) { result in
                XCTAssertTrue(result.isFailure)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 3)
    }

    // MARK: - Private

    private func launchShell() throws -> EmbeddedShell {
        let exp = XCTestExpectation()
        var shell: EmbeddedShell?
        let connection = try launchConnection()
        connection.requestShell(withTimeout: 15) { result in
            switch result {
            case .success(let success):
                shell = EmbeddedShell(shell: success)
            case .failure:
                break
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
        if let shell = shell {
            return shell
        }
        struct AError: Error {}
        throw AError()
    }

    private func launchConnection() throws -> SSHConnection {
        let exp = XCTestExpectation()
        connection.start(withTimeout: 2) { result in
            XCTAssertTrue(result.isSuccess)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        return connection
    }
}

private class EmbeddedShell {
    let shell: SSHShell

    var state: SSHShell.State {
        shell.state
    }

    private(set) var states: [SSHShell.State] = []
    private(set) var data: [Data] = []

    init(shell: SSHShell) {
        self.shell = shell
        self.shell.stateUpdateHandler = { state in
            self.states.append(state)
        }
        self.shell.readHandler = { data in
            self.data.append(data)
        }
    }
}
