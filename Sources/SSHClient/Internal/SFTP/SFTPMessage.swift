import Foundation
import NIO

typealias Promise<T> = EventLoopPromise<T>
typealias Future<T> = EventLoopFuture<T>

typealias SFTPFileHandle = ByteBuffer
typealias SFTPRequestID = UInt32

public struct SFTPPathComponent: Sendable {
    public let filename: String
    public let longname: String
    public let attributes: SFTPFileAttributes

    init(filename: String, longname: String, attributes: SFTPFileAttributes) {
        self.filename = filename
        self.longname = longname
        self.attributes = attributes
    }
}

struct SFTPFileListing {
    let path: [SFTPPathComponent]

    init(path: [SFTPPathComponent]) {
        self.path = path
    }
}

extension SFTPMessage.ReadFile {
    enum Response {
        case fileData(SFTPMessage.FileData)
        case status(SFTPMessage.Status)
    }
}

extension SFTPMessage.ReadDir {
    enum Response {
        case name(SFTPMessage.Name)
        case status(SFTPMessage.Status)
    }
}

enum SFTPResponse {
    case version(SFTPMessage.Version)
    case handle(SFTPMessage.Handle)
    case status(SFTPMessage.Status)
    case data(SFTPMessage.FileData)
    case mkdir(SFTPMessage.MkDir)
    case name(SFTPMessage.Name)
    case attributes(SFTPMessage.Attributes)

    var id: SFTPRequestID? {
        message.requestID
    }

    var message: SFTPMessage {
        switch self {
        case .version(let message):
            return .version(message)
        case .handle(let message):
            return .handle(message)
        case .status(let message):
            return .status(message)
        case .data(let message):
            return .data(message)
        case .mkdir(let message):
            return .mkdir(message)
        case .name(let message):
            return .name(message)
        case .attributes(let message):
            return .attributes(message)
        }
    }

    init?(message: SFTPMessage) {
        switch message {
        case .handle(let message):
            self = .handle(message)
        case .status(let message):
            self = .status(message)
        case .data(let message):
            self = .data(message)
        case .mkdir(let message):
            self = .mkdir(message)
        case .name(let message):
            self = .name(message)
        case .attributes(let message):
            self = .attributes(message)
        case .version(let version):
            self = .version(version)
        case .realpath,
             .openFile,
             .fstat,
             .closeFile,
             .read,
             .write,
             .initialize,
             .stat,
             .lstat,
             .rmdir,
             .opendir,
             .readdir,
             .remove,
             .fsetstat,
             .setstat,
             .symlink,
             .readlink,
             .rename:
            return nil
        }
    }
}

enum SFTPMessage {
    struct Initialize {
        let version: SFTPProtocolVersion
    }

    struct Version {
        let version: SFTPProtocolVersion
        var extensionData: [(String, String)]
    }

    struct OpenFile {
        struct Payload {
            // Called `filename` in spec
            var filePath: String
            var pFlags: SFTPOpenFileFlags
            var attributes: SFTPFileAttributes
        }

        let requestId: SFTPRequestID
        let payload: Payload
    }

    struct CloseFile {
        let requestId: SFTPRequestID
        var handle: SFTPFileHandle
    }

    struct ReadFile {
        struct Payload {
            var handle: SFTPFileHandle
            var offset: UInt64
            var length: UInt32
        }

        let requestId: SFTPRequestID
        var payload: Payload
    }

    struct WriteFile {
        struct Payload {
            var handle: SFTPFileHandle
            var offset: UInt64
            var data: ByteBuffer
        }

        let requestId: SFTPRequestID
        var payload: Payload
    }

    struct Status: Error {
        struct Payload {
            var errorCode: SFTPStatusCode
            var message: String
            var languageTag: String
        }

        let requestId: SFTPRequestID
        var payload: Payload
    }

    struct Handle {
        let requestId: SFTPRequestID
        var handle: SFTPFileHandle
    }

    struct FileStat {
        let requestId: SFTPRequestID
        var handle: SFTPFileHandle
    }

    struct Remove {
        let requestId: SFTPRequestID
        var filename: String
    }

    struct FileSetStat {
        struct Payload {
            var handle: SFTPFileHandle
            var attributes: SFTPFileAttributes
        }

        let requestId: SFTPRequestID
        var payload: Payload
    }

    struct SetStat {
        struct Payload {
            var path: String
            var attributes: SFTPFileAttributes
        }

        let requestId: SFTPRequestID
        var payload: Payload
    }

    struct Symlink {
        struct Payload {
            var linkPath: String
            var targetPath: String
        }

        let requestId: SFTPRequestID
        var payload: Payload
    }

    struct Readlink {
        let requestId: SFTPRequestID
        var path: String
    }

    struct FileData {
        let requestId: SFTPRequestID
        var data: ByteBuffer
    }

    struct MkDir {
        struct Payload {
            let filePath: String
            let attributes: SFTPFileAttributes
        }

        let requestId: SFTPRequestID
        var payload: Payload
    }

    struct RmDir {
        let requestId: SFTPRequestID
        var filePath: String
    }

    struct OpenDir {
        let requestId: SFTPRequestID
        var path: String
    }

    struct Stat {
        static let id = SFTPMessageType.stat

        let requestId: SFTPRequestID
        var path: String
    }

    struct LStat {
        let requestId: SFTPRequestID
        var path: String
    }

    struct RealPath {
        let requestId: SFTPRequestID
        var path: String
    }

    struct Name {
        let requestId: SFTPRequestID
        var count: UInt32 { UInt32(components.count) }
        var components: [SFTPPathComponent]
    }

    struct Attributes {
        let requestId: SFTPRequestID
        var attributes: SFTPFileAttributes
    }

    struct ReadDir {
        let requestId: SFTPRequestID
        var handle: SFTPFileHandle
    }

    struct Rename {
        struct Payload {
            let oldPath: String
            let newPath: String
        }

        let requestId: SFTPRequestID
        let payload: Payload
    }

    /// Client.
    ///
    /// Starts SFTP session and indicates client version.
    /// Response is `version`.
    case initialize(Initialize)

    /// Server.
    ///
    /// Indicates server version and supported extensions.
    case version(Version)

    /// Client.
    ///
    /// Receives `handle` on success and `status` on failure
    case openFile(OpenFile)

    /// Client.
    ///
    /// Close file immediately invaldiates the handle
    /// The only valid response is `status`
    case closeFile(CloseFile)

    /// Client.
    ///
    /// Response is `data` on success or `status` on failure.
    case read(ReadFile)

    /// Client.
    ///
    /// Response is `status`.
    case write(WriteFile)

    /// Server.
    ///
    /// Successfully opened a file
    case handle(Handle)

    /// Server.
    ///
    /// Successfully closed a file, or failed to open a file
    case status(Status)

    /// Server.
    ///
    /// Data read from file.
    case data(FileData)

    /// Server.
    ///
    /// No response, directory gets created or an error is thrown.
    case mkdir(MkDir)

    case rmdir(RmDir)
    case opendir(OpenDir)
    case stat(Stat)
    case fstat(FileStat)
    case remove(Remove)
    case fsetstat(FileSetStat)
    case setstat(SetStat)
    case symlink(Symlink)
    case readlink(Readlink)
    case lstat(LStat)
    case realpath(RealPath)
    case name(Name)
    case attributes(Attributes)
    case readdir(ReadDir)
    case rename(Rename)

    var requestID: SFTPRequestID? {
        switch self {
        case .initialize, .version:
            return nil
        case .openFile(let openFile):
            return openFile.requestId
        case .closeFile(let closeFile):
            return closeFile.requestId
        case .read(let readFile):
            return readFile.requestId
        case .write(let writeFile):
            return writeFile.requestId
        case .handle(let handle):
            return handle.requestId
        case .status(let status):
            return status.requestId
        case .data(let fileData):
            return fileData.requestId
        case .mkdir(let mkDir):
            return mkDir.requestId
        case .rmdir(let rmDir):
            return rmDir.requestId
        case .opendir(let openDir):
            return openDir.requestId
        case .stat(let stat):
            return stat.requestId
        case .fstat(let fileStat):
            return fileStat.requestId
        case .remove(let remove):
            return remove.requestId
        case .fsetstat(let fileSetStat):
            return fileSetStat.requestId
        case .setstat(let setStat):
            return setStat.requestId
        case .symlink(let symlink):
            return symlink.requestId
        case .readlink(let readlink):
            return readlink.requestId
        case .lstat(let lStat):
            return lStat.requestId
        case .realpath(let realPath):
            return realPath.requestId
        case .name(let name):
            return name.requestId
        case .attributes(let attributes):
            return attributes.requestId
        case .readdir(let readDir):
            return readDir.requestId
        case .rename(let rename):
            return rename.requestId
        }
    }
}
