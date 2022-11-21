
import Foundation
import SSHClient

class SFTPServer {

    private let fileManager: FileManager
    private let configuration: Configuration

    // MARK: - Credentials

    var host: String {
        configuration.host
    }

    var port: UInt16 {
        UInt16(configuration.port)
    }

    var password: String {
        configuration.password
    }

    var username: String {
        credentials.username
    }

    var credentials: SSHAuthentication {
        .init(
            username: configuration.username,
            method: .password(.init(password)),
            hostKeyValidation: .acceptAll()
        )
    }

    // MARK: - Life Cycle

    init(configuration: Configuration) {
        self.configuration = configuration
        self.fileManager = .default
        fileManager.changeCurrentDirectoryPath("../")
    }

    // MARK: - Files

    func preferredWorkingDirectoryPath(components: String? = nil) -> String {
        let url = URL(fileURLWithPath: configuration.workingDirectory)
        if let components = components {
            return url.appendingPathComponent(components).path
        }
        return url.path
    }

    func itemModificationDate(atPath path: String) -> Date? {
        return try? fileManager.attributesOfItem(atPath: resolvePath(path))[.modificationDate] as? Date
    }

    func createDirectory(atPath path: String) throws {
        let resolved = resolvePath(path)
        return try fileManager.createDirectory(
            at: URL(fileURLWithPath: resolved),
            withIntermediateDirectories: true
        )
    }

    func contentOfFile(atPath path: String) -> Data? {
        fileManager.contents(atPath: resolvePath(path))
    }

    func removeItem(atPath path: String) throws {
        try fileManager.removeItem(at: URL(fileURLWithPath: resolvePath(path)))
    }

    func directoryContent(atPath path: String) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: resolvePath(path))
    }

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: resolvePath(path))
    }

    func createFile(atPath path: String, contents: Data?) {
        fileManager.createFile(atPath: resolvePath(path), contents: contents)
    }

    func createRandomFiles(atPath path: String, count: Int) -> [String] {
        let url = URL(fileURLWithPath: resolvePath(path))
        let id = UUID().uuidString
        var names: [String] = []
        for i in 0..<count {
            let name = "\(i)_\(id)"
            names.append(name)
            let fileURL = url.appendingPathComponent("\(i)_\(id)")
            fileManager.createFile(
                atPath: fileURL.path,
                contents: nil
            )
        }
        return names
    }

    private func resolvePath(_ path: String) -> String {
        configuration.urlResolver(path)
    }
}

extension SFTPServer {

    struct Configuration {
        let username: String
        let password: String
        let host: String
        let port: Int
        let workingDirectory: String
        let urlResolver: (String) -> String

        static let local = Configuration(
            username: "YOUR_USERNAME",
            password: "YOUR_PASSWORD",
            host: "localhost",
            port: 22,
            workingDirectory: "YOUR_TEST_DIRECTORY",
            urlResolver: { path in path }
        )

        static let docker = Configuration(
            username: "user",
            password: "password",
            host: "127.0.0.1",
            port: 2222,
            workingDirectory: "home/",
            urlResolver: { path in
                URL(fileURLWithPath: ProcessInfo.processInfo.environment["WORKING_DIR"]!)
                    .appendingPathComponent("Tests/Scripts/distant/user")
                    .appendingPathComponent(path)
                    .path
            }
        )
    }
}
