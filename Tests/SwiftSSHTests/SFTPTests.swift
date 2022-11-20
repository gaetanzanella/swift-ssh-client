
import Foundation
import SwiftSSH
import XCTest

class SFTPTests: XCTestCase {

    var sftpServer: SFTPServer!
    var connection: SSHConnection!
    var client: SFTPClient!

    override func setUp() {
        sftpServer = SFTPServer(configuration: .docker)
        connection = SSHConnection(
            host: sftpServer.host,
            port: sftpServer.port,
            authentication: sftpServer.credentials
        )
        try! sftpServer.createDirectory(
            atPath: sftpServer.preferredWorkingDirectoryPath()
        )
    }

    override func tearDown() {
        connection.end {}
        try! sftpServer.removeItem(
            atPath: sftpServer.preferredWorkingDirectoryPath()
        )
    }

    // MARK: - Connection

    func testSFTPClientLaunch() throws {
        _ = try launchSFTPClient()
    }

    func testMkDir() throws {
        let client = try launchSFTPClient()
        let path = sftpServer.preferredWorkingDirectoryPath(components: "new")
        let exp = XCTestExpectation()
        client.createDirectory(
            atPath: path
        ) { result in
            switch result {
            case .success:
                XCTAssertTrue(self.sftpServer.fileExists(atPath: path))
            case let .failure(error):
                XCTFail(error.localizedDescription)
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testListDirectory() throws {
        let client = try launchSFTPClient()
        let path = sftpServer.preferredWorkingDirectoryPath(components: "new")
        try sftpServer.createDirectory(atPath: path)
        let files = sftpServer.createRandomFiles(atPath: path, count: 10)
        let exp = XCTestExpectation()
        client.listDirectory(atPath: path) { result in
            switch result {
            case let .success(content):
                let received = content.map { $0.filename }
                XCTAssertEqual(
                    received.sorted(),
                    (files + [".", ".."]).sorted()
                )
            case let .failure(error):
                XCTFail(error.localizedDescription)
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - File

    func testFileCreation() throws {
        let client = try launchSFTPClient()
        let path = sftpServer.preferredWorkingDirectoryPath(components: "file.test")
        // without create
        let exp1 = XCTestExpectation()
        let inner1 = XCTestExpectation()
        inner1.isInverted = true
        client.withFile(filePath: path, flags: []) { file, completion in
            inner1.fulfill()
            completion()
        } completion: { result in
            XCTAssertTrue(result.isFailure)
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 1.0)
        wait(for: [inner1], timeout: 1.0)
        // with create
        let exp = XCTestExpectation()
        let inner = XCTestExpectation()
        client.withFile(filePath: path, flags: [.create]) { file, completion in
            inner.fulfill()
            completion()
        } completion: { result in
            switch result {
            case .failure:
                XCTFail()
            case .success:
                XCTAssertEqual(
                    Data(),
                    self.sftpServer.contentOfFile(atPath: path)
                )
            }
            exp.fulfill()
        }
        wait(for: [inner, exp], timeout: 1.0)
    }

    func testFileForceCreation() throws {
        let client = try launchSFTPClient()
        let path = sftpServer.preferredWorkingDirectoryPath(components: "file.test")
        sftpServer.createFile(atPath: path, contents: "hello.world".data(using: .utf8)!)
        let exp = XCTestExpectation()
        let inner = XCTestExpectation()
        inner.isInverted = true
        client.withFile(filePath: path, flags: [.create, .forceCreate]) { file, completion in
            inner.fulfill()
            completion()
        } completion: { result in
            XCTAssertTrue(result.isFailure)
            exp.fulfill()
        }
        wait(for: [inner, exp], timeout: 1.0)
    }

    func testExistingFileTruncating() throws {
        let client = try launchSFTPClient()
        let path = sftpServer.preferredWorkingDirectoryPath(components: "file.test")
        sftpServer.createFile(atPath: path, contents: "hello.world".data(using: .utf8)!)
        let exp = XCTestExpectation()
        let inner = XCTestExpectation()
        client.withFile(filePath: path, flags: [.truncate]) { file, completion in
            inner.fulfill()
            completion()
        } completion: { result in
            switch result {
            case .failure:
                XCTFail()
            case .success:
                XCTAssertEqual(
                    Data(),
                    self.sftpServer.contentOfFile(atPath: path)
                )
            }
            exp.fulfill()
        }
        wait(for: [inner, exp], timeout: 1.0)
    }

    func testFileReading() throws {
        let client = try launchSFTPClient()
        let path = sftpServer.preferredWorkingDirectoryPath(components: "file.test")
        let fileContent = "hello.world".data(using: .utf8)!
        sftpServer.createFile(atPath: path, contents: fileContent)
        let exp = XCTestExpectation()
        let inner = XCTestExpectation()
        client.withFile(filePath: path, flags: [.read]) { file, completion in
            let group = DispatchGroup()
            // all
            group.enter()
            file.read { result in
                switch result {
                case let .success(data):
                    XCTAssertEqual(
                        data,
                        fileContent
                    )
                case .failure:
                    XCTFail()
                }
                group.leave()
            }
            // partial
            group.enter()
            let slice = 3..<5
            file.read(from: UInt64(slice.lowerBound), length: UInt32(slice.count)) { result in
                switch result {
                case let .success(data):
                    XCTAssertEqual(
                        data,
                        fileContent[slice]
                    )
                case .failure:
                    XCTFail()
                }
                group.leave()
            }
            group.notify(queue: .main) {
                completion()
                inner.fulfill()
            }
        } completion: { result in
            XCTAssertTrue(result.isSuccess)
            exp.fulfill()
        }
        wait(for: [inner, exp], timeout: 1.0)
    }

    func testFileWriting() throws {
        let client = try launchSFTPClient()
        let path = sftpServer.preferredWorkingDirectoryPath(components: "file.test")
        sftpServer.createFile(atPath: path, contents: nil)
        let exp = XCTestExpectation()
        let inner = XCTestExpectation()
        client.withFile(
            filePath: path,
            flags: .write,
            { file, completion in
                let first = "helloworld".data(using: .utf8)!
                // write
                file.write(first) { result in
                    XCTAssertTrue(result.isSuccess)
                    XCTAssertEqual(
                        first,
                        self.sftpServer.contentOfFile(atPath: path)
                    )
                    // replace
                    let second = "georges".data(using: .utf8)!
                    file.write(second, at: 5) { result in
                        XCTAssertTrue(result.isSuccess)
                        XCTAssertEqual(
                            "hellogeorges".data(using: .utf8)!,
                            self.sftpServer.contentOfFile(atPath: path)
                        )
                        completion()
                        inner.fulfill()
                    }
                }
            },
            completion: { result in
                XCTAssertTrue(result.isSuccess)
                exp.fulfill()
            }
        )
        wait(for: [inner, exp], timeout: 1.0)
    }

    func testFileAppending() throws {
        let client = try launchSFTPClient()
        let path = sftpServer.preferredWorkingDirectoryPath(components: "file.test")
        sftpServer.createFile(atPath: path, contents: "hellowo".data(using: .utf8)!)
        let exp = XCTestExpectation()
        let inner = XCTestExpectation()
        client.withFile(
            filePath: path,
            flags: [.write, .append],
            { file, completion in
                file.write(
                    "rld!".data(using: .utf8)!,
                    at: 2 // should be ignored
                ) { result in
                    XCTAssertTrue(result.isSuccess)
                    XCTAssertEqual(
                        "helloworld!".data(using: .utf8)!,
                        self.sftpServer.contentOfFile(atPath: path)
                    )
                    inner.fulfill()
                    completion()
                }
            },
            completion: { result in
                XCTAssertTrue(result.isSuccess)
                exp.fulfill()
            }
        )
        wait(for: [inner, exp], timeout: 1.0)
    }

    func testFileFlagPermissions() throws {
        let client = try launchSFTPClient()
        let path = sftpServer.preferredWorkingDirectoryPath(components: "file.test")
        sftpServer.createFile(atPath: path, contents: "helloworld".data(using: .utf8)!)
        // read
        let expRead = XCTestExpectation()
        let innerRead = XCTestExpectation()
        client.withFile(filePath: path, flags: .read) { file, completion in
            file.write("data".data(using: .utf8)!) { result in
                XCTAssertTrue(result.isFailure)
                completion()
                innerRead.fulfill()
            }
        } completion: { result in
            XCTAssertTrue(result.isSuccess)
            expRead.fulfill()
        }
        wait(for: [expRead, innerRead], timeout: 1.0)
        // write
        let expWrite = XCTestExpectation()
        let innerWrite = XCTestExpectation()
        client.withFile(filePath: path, flags: .write) { file, completion in
            file.read { result in
                XCTAssertTrue(result.isFailure)
                completion()
                innerWrite.fulfill()
            }
        } completion: { result in
            XCTAssertTrue(result.isSuccess)
            expWrite.fulfill()
        }
        wait(for: [expWrite, innerWrite], timeout: 1.0)
    }

    func testFileAttributes() throws {
        let client = try launchSFTPClient()
        let path = sftpServer.preferredWorkingDirectoryPath(components: "test")
        let data = "hello".data(using: .utf8)!
        sftpServer.createFile(
            atPath: path,
            contents: data
        )
        let modificationDate = sftpServer.itemModificationDate(atPath: path)
        // from client
        let exp = XCTestExpectation()
        client.getAttributes(at: path) { (result: Result<SFTPFileAttributes, Error>) -> Void in
            switch result {
            case .success(let attributes):
                XCTAssertEqual(data.count, attributes.size.flatMap { Int($0) })
                XCTAssertEqual(
                    attributes.accessModificationTime?.modificationTime.timeIntervalSince1970.rounded(.down),
                    modificationDate?.timeIntervalSince1970.rounded(.down)
                )
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 60.0)
        // from file handle
        let fileExp = XCTestExpectation()
        let fileInnerExp = XCTestExpectation()
        client.withFile(filePath: path, flags: []) { file, completion in
            file.readAttributes { result in
                switch result {
                case .success(let attributes):
                    XCTAssertEqual(data.count, attributes.size.flatMap { Int($0) })
                    XCTAssertEqual(
                        attributes.accessModificationTime?.modificationTime.timeIntervalSince1970.rounded(.down),
                        modificationDate?.timeIntervalSince1970.rounded(.down)
                    )
                case .failure:
                    XCTFail()
                }
                completion()
                fileInnerExp.fulfill()
            }
        } completion: { result in
            XCTAssertTrue(result.isSuccess)
            fileExp.fulfill()
        }
        wait(for: [fileExp, fileInnerExp], timeout: 3)
    }

    // MARK: - Performances

    func testBatchingRequests() throws {
        let client = try launchSFTPClient()
        let rootPath = sftpServer.preferredWorkingDirectoryPath()
        let filePath = sftpServer.preferredWorkingDirectoryPath(components: "test.test")
        sftpServer.createFile(atPath: filePath, contents: "helloworld".data(using: .utf8)!)
        let group = DispatchGroup()
        let exp = XCTestExpectation()
        for _ in 0..<100 {
            group.enter()
            client.getAttributes(at: filePath) { result in
                group.leave()
                XCTAssertTrue(result.isSuccess)
            }
            group.enter()
            client.listDirectory(atPath: rootPath) { result in
                group.leave()
                XCTAssertTrue(result.isSuccess)
            }
        }
        group.notify(queue: .main) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    // MARK: - Closing

    func testClosing() throws {
        let client = try launchSFTPClient()
        let exp = XCTestExpectation()
        client.close {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
    }

    // MARK: - Moving

    func testMovingFile() throws {
        let client = try launchSFTPClient()
        let filePath = sftpServer.preferredWorkingDirectoryPath(components: "test.test")
        let fileContent = "helloworld".data(using: .utf8)!
        sftpServer.createFile(atPath: filePath, contents: fileContent)
        let newPath = sftpServer.preferredWorkingDirectoryPath(components: "new/new.test")
        try sftpServer.createDirectory(atPath: sftpServer.preferredWorkingDirectoryPath(components: "new"))
        let exp = XCTestExpectation()
        client.moveItem(atPath: filePath, toPath: newPath) { result in
            XCTAssertTrue(result.isSuccess)
            XCTAssertFalse(self.sftpServer.fileExists(atPath: filePath))
            XCTAssertEqual(
                self.sftpServer.contentOfFile(atPath: newPath),
                fileContent
            )
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
    }

    func testMovingDirectory() throws {
        let client = try launchSFTPClient()
        // first
        let dir1Path = sftpServer.preferredWorkingDirectoryPath(components: "DIR1")
        try sftpServer.createDirectory(atPath: dir1Path)
        let filePath = sftpServer.preferredWorkingDirectoryPath(components: "DIR1/file.test")
        let fileContent = "helloworld".data(using: .utf8)!
        sftpServer.createFile(atPath: filePath, contents: fileContent)

        // second
        let dir2Path = sftpServer.preferredWorkingDirectoryPath(components: "DIR2")
        try sftpServer.createDirectory(atPath: dir2Path)
        let dst = sftpServer.preferredWorkingDirectoryPath(components: "DIR2/DIR1_NEW")
        let fileDst = sftpServer.preferredWorkingDirectoryPath(components: "DIR2/DIR1_NEW/file.test")
        let exp = XCTestExpectation()
        client.moveItem(atPath: dir1Path, toPath: dst) { result in
            XCTAssertTrue(result.isSuccess)
            XCTAssertFalse(self.sftpServer.fileExists(atPath: dir1Path))
            XCTAssertTrue(self.sftpServer.fileExists(atPath: dst))
            XCTAssertEqual(
                self.sftpServer.contentOfFile(atPath: fileDst),
                fileContent
            )
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
    }

    // MARK: - Deleting

    func testDeletingFile() throws {
        let client = try launchSFTPClient()
        let filePath = sftpServer.preferredWorkingDirectoryPath(components: "test.test")
        let fileContent = "helloworld".data(using: .utf8)!
        sftpServer.createFile(atPath: filePath, contents: fileContent)
        XCTAssertTrue(self.sftpServer.fileExists(atPath: filePath))
        let exp = XCTestExpectation()
        client.removeFile(atPath: filePath) { result in
            XCTAssertTrue(result.isSuccess)
            XCTAssertFalse(self.sftpServer.fileExists(atPath: filePath))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
    }

    func testDeletingDirectory() throws {
        let client = try launchSFTPClient()
        let filePath = sftpServer.preferredWorkingDirectoryPath(components: "test")
        try sftpServer.createDirectory(atPath: filePath)
        XCTAssertTrue(self.sftpServer.fileExists(atPath: filePath))
        let exp = XCTestExpectation()
        client.removeDirectory(atPath: filePath) { result in
            XCTAssertTrue(result.isSuccess)
            XCTAssertFalse(self.sftpServer.fileExists(atPath: filePath))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
    }

    // MARK: - Errors

    func testDisconnectionError() throws {
        let client = try launchSFTPClient()
        let filePath = sftpServer.preferredWorkingDirectoryPath(components: "test.test")
        sftpServer.createFile(atPath: filePath, contents: "helloworld".data(using: .utf8)!)
        let exp = XCTestExpectation()
        let inner = XCTestExpectation()
        client.withFile(filePath: filePath, flags: [.write, .read]) { file, completion in
            file.read { result in
                XCTAssertTrue(result.isFailure)
                inner.fulfill()
                completion()
            }
            self.connection.end {}
        } completion: { result in
            XCTAssertTrue(result.isFailure)
            exp.fulfill()
        }
        wait(for: [exp, inner], timeout: 7)
    }

    func testUnavailableSFTPConnectionError() throws {
        let newConnection = SSHConnection(
            host: connection.host,
            port: connection.port + 1,
            authentication: connection.authentication
        )
        let sshServerWithoutSFTP = SSHServer(
            expectedUsername: newConnection.authentication.username,
            expectedPassword: sftpServer.password,
            host: newConnection.host,
            port: newConnection.port
        )
        try sshServerWithoutSFTP.run()
        defer {
            sshServerWithoutSFTP.end()
        }
        let exp = XCTestExpectation()
        newConnection.start(withTimeout: 2) { result in
            switch result {
            case .success:
                self.connection.requestSFTPClient(withTimeout: 3) { result in
                    XCTAssertTrue(result.isFailure)
                    exp.fulfill()
                }
            case .failure:
                XCTFail()
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 3)
    }

    func testTimeoutError() throws {
        let exp = XCTestExpectation()
        connection.start(withTimeout: 2) { result in
            XCTAssertTrue(result.isSuccess)
            self.connection.requestSFTPClient(withTimeout: 0.2) { result in
                XCTAssertTrue(result.isFailure)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 3)
    }

    // MARK: - Private

    private func launchSFTPClient() throws -> SFTPClient {
        let exp = XCTestExpectation()
        var sftpClient: SFTPClient?
        connection.start(withTimeout: 2) { result in
            switch result {
            case .success:
                self.connection.requestSFTPClient(withTimeout: 15) { result in
                    switch result {
                    case .success(let success):
                        sftpClient = success
                    case .failure:
                        break
                    }
                    exp.fulfill()
                }
            case .failure:
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 3)
        if let sftpClient = sftpClient {
            return sftpClient
        }
        struct AError: Error {}
        throw AError()
    }
}
