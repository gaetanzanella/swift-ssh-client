
import Foundation
import SSHClient
import XCTest

class SSHConnectionTests: XCTestCase {
    var server: SSHServer!

    override func setUp() {
        server = SSHServer(
            expectedUsername: "user",
            expectedPassword: "password",
            host: "localhost",
            port: 23
        )
        try! server.run()
    }

    override func tearDown() {
        server.end()
    }

    // MARK: - Connection

    func testSuccessfulConnection() throws {
        let connection = EmbeddedConnection(
            host: server.host,
            port: server.port,
            username: server.username,
            password: server.password
        )
        let expect = XCTestExpectation()
        XCTAssertFalse(server.hasActiveChild)
        connection.ssh.start(withTimeout: 3) { result in
            XCTAssertTrue(result.isSuccess)
            XCTAssertEqual(connection.state, .ready)
            XCTAssertEqual(connection.updates, [.ready])
            XCTAssertTrue(self.server.hasActiveChild)
            expect.fulfill()
        }
        wait(for: [expect], timeout: 3)
    }

    func testWrongPortConnection() throws {
        let connection = EmbeddedConnection(
            host: server.host,
            port: server.port + 1,
            username: server.username,
            password: server.password
        )
        let expect = XCTestExpectation()
        connection.ssh.start(withTimeout: 3) { result in
            XCTAssertTrue(result.isFailure)
            XCTAssertEqual(connection.updates, [.failed(.unknown)])
            XCTAssertFalse(self.server.hasActiveChild)
            expect.fulfill()
        }
        wait(for: [expect], timeout: 3)
    }

    func testWrongAuthenticationConnection() throws {
        let connection = EmbeddedConnection(
            host: server.host,
            port: server.port,
            username: server.username + "wrong",
            password: server.password + "wrong"
        )
        let expect = XCTestExpectation()
        connection.ssh.start(withTimeout: 1.0) { result in
            XCTAssertTrue(result.isFailure)
            /* Seems like the only way to detect failure is to use a timeout :/  */
            XCTAssertEqual(connection.state, .failed(.timeout))
            XCTAssertEqual(connection.updates, [.failed(.timeout)])
            self.wait(timeout: 0.2)
            XCTAssertFalse(self.server.hasActiveChild)
            expect.fulfill()
        }
        wait(for: [expect], timeout: 3)
    }

    func testTimeoutConnection() throws {
        let connection = EmbeddedConnection(
            host: server.host,
            port: server.port,
            username: server.username,
            password: server.password
        )
        server.timeBeforeAuthentication = 3.0
        let expect = XCTestExpectation()
        connection.ssh.start(withTimeout: 1.0) { result in
            XCTAssertTrue(result.isFailure)
            XCTAssertEqual(connection.state, .failed(.timeout))
            XCTAssertEqual(connection.updates, [.failed(.timeout)])
            self.wait(timeout: 0.1)
            XCTAssertFalse(self.server.hasActiveChild)
            expect.fulfill()
        }
        wait(for: [expect], timeout: 3)
    }

    func testDisconnection() throws {
        let connection = EmbeddedConnection(
            host: server.host,
            port: server.port,
            username: server.username,
            password: server.password
        )
        let connectionExp = XCTestExpectation()
        connection.ssh.start(withTimeout: 3.0) { _ in connectionExp.fulfill() }
        wait(for: [connectionExp], timeout: 3)
        XCTAssertTrue(server.hasActiveChild)
        let disconnectionExp = XCTestExpectation()
        connection.ssh.end {
            XCTAssertEqual(connection.state, .idle)
            XCTAssertEqual(connection.updates, [.ready, .idle])
            self.wait(timeout: 0.1)
            XCTAssertFalse(self.server.hasActiveChild)
            disconnectionExp.fulfill()
        }
        wait(for: [disconnectionExp], timeout: 3.0)
    }

    func testFastDisconnection() throws {
        let connection = EmbeddedConnection(
            host: server.host,
            port: server.port,
            username: server.username,
            password: server.password
        )
        server.timeBeforeAuthentication = 2.0
        let connect1 = XCTestExpectation()
        let connect2 = XCTestExpectation()
        connect1.isInverted = true
        connection.ssh.start(withTimeout: 3.0) { result in
            connect1.fulfill()
            XCTAssertTrue(result.isFailure)
            connect2.fulfill()
            XCTAssertFalse(self.server.hasActiveChild)
        }
        wait(for: [connect1], timeout: 1.0)
        let disconnectionExp = XCTestExpectation()
        connection.ssh.end {
            XCTAssertEqual(connection.state, .idle)
            XCTAssertEqual(connection.updates, [])
            disconnectionExp.fulfill()
            self.wait(timeout: 0.1)
            XCTAssertFalse(self.server.hasActiveChild)
        }
        wait(for: [connect2, disconnectionExp], timeout: 3.0)
    }

    func testServerEnd() throws {
        let connection = EmbeddedConnection(
            host: server.host,
            port: server.port,
            username: server.username,
            password: server.password
        )
        let connect = XCTestExpectation()
        connection.ssh.start(withTimeout: 1) { _ in
            connect.fulfill()
        }
        wait(for: [connect], timeout: 1)
        server.end()
        wait(timeout: 0.3)
        XCTAssertEqual(connection.updates, [.ready, .idle])
    }

    func testReconnection() throws {
        let connection = EmbeddedConnection(
            host: server.host,
            port: server.port,
            username: server.username,
            password: server.password
        )
        let expect = XCTestExpectation()
        expect.expectedFulfillmentCount = 3
        connection.ssh.start(withTimeout: 1) { _ in
            expect.fulfill()
            XCTAssertTrue(self.server.hasActiveChild)
            connection.ssh.end {
                self.wait(timeout: 0.1)
                XCTAssertFalse(self.server.hasActiveChild)
                expect.fulfill()
                connection.ssh.start(withTimeout: 1, completion: { _ in
                    expect.fulfill()
                    XCTAssertTrue(self.server.hasActiveChild)
                })
            }
        }
        wait(for: [expect], timeout: 2)
        XCTAssertEqual(connection.updates, [.ready, .idle, .ready])
    }

    // MARK: - Shell
}

class EmbeddedConnection {
    let ssh: SSHConnection

    var state: SSHConnection.State {
        ssh.state
    }

    private(set) var updates: [SSHConnection.State] = []

    init(host: String, port: UInt16, username: String, password: String) {
        ssh = SSHConnection(
            host: host,
            port: port,
            authentication: .init(
                username: username,
                method: .password(.init(password)),
                hostKeyValidation: .acceptAll()
            )
        )
        ssh.stateUpdateHandler = { state in
            self.updates.append(state)
        }
    }
}
