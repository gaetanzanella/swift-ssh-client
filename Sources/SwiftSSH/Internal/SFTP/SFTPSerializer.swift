import NIO

final class SFTPMessageSerializer: MessageToByteEncoder {
    typealias OutboundIn = SFTPMessage
    
    func encode(data: SFTPMessage, out: inout ByteBuffer) throws {
        let lengthIndex = out.writerIndex
        out.moveWriterIndex(forwardBy: 4)
        out.writeInteger(data.type.rawValue)
        switch data {
        case .initialize(let initialize):
            out.writeInteger(initialize.version.rawValue)
        case .version(let version):
            out.writeInteger(version.version.rawValue)
            for (key, value) in version.extensionData {
                out.writeSSHString(key)
                out.writeSSHString(value)
            }
        case .openFile(let openFile):
            out.writeInteger(openFile.requestId)
            out.writeSSHString(openFile.payload.filePath)
            out.writeInteger(openFile.payload.pFlags.rawValue)
            out.writeSFTPFileAttributes(openFile.payload.attributes)
        case .closeFile(var closeFile):
            out.writeInteger(closeFile.requestId)
            out.writeSSHString(&closeFile.handle)
        case .read(var read):
            out.writeInteger(read.requestId)
            out.writeSSHString(&read.payload.handle)
            out.writeInteger(read.payload.offset)
            out.writeInteger(read.payload.length)
        case .write(var write):
            out.writeInteger(write.requestId)
            out.writeSSHString(&write.payload.handle)
            out.writeInteger(write.payload.offset)
            out.writeSSHString(&write.payload.data)
        case .handle(var handle):
            out.writeInteger(handle.requestId)
            out.writeSSHString(&handle.handle)
        case .status(let status):
            out.writeInteger(status.requestId)
            out.writeInteger(status.payload.errorCode.rawValue)
            out.writeSSHString(status.payload.message)
            out.writeSSHString(status.payload.languageTag)
        case .data(var data):
            out.writeInteger(data.requestId)
            out.writeSSHString(&data.data)
        case .mkdir(let mkdir):
            out.writeInteger(mkdir.requestId)
            out.writeSSHString(mkdir.payload.filePath)
            out.writeSFTPFileAttributes(mkdir.payload.attributes)
        case .rmdir(let rmdir):
            out.writeInteger(rmdir.requestId)
            out.writeSSHString(rmdir.filePath)
        case .stat(let stat):
            out.writeInteger(stat.requestId)
            out.writeSSHString(stat.path)
        case .lstat(let lstat):
            out.writeInteger(lstat.requestId)
            out.writeSSHString(lstat.path)
        case .attributes(let fstat):
            out.writeInteger(fstat.requestId)
            out.writeSFTPFileAttributes(fstat.attributes)
        case .realpath(let realPath):
            out.writeInteger(realPath.requestId)
            out.writeSSHString(realPath.path)
        case .name(let name):
            out.writeInteger(name.requestId)
            out.writeInteger(name.count)
            for component in name.components {
                out.writeSSHString(component.filename)
                out.writeSSHString(component.longname)
                out.writeSFTPFileAttributes(component.attributes)
            }
        case .opendir(let opendir):
            out.writeInteger(opendir.requestId)
            out.writeSSHString(opendir.path)
        case .readdir(var readdir):
            out.writeInteger(readdir.requestId)
            out.writeSSHString(&readdir.handle)
        case .fstat(var fstat):
            out.writeInteger(fstat.requestId)
            out.writeSSHString(&fstat.handle)
        case .remove(let remove):
            out.writeSSHString(remove.filename)
        case .fsetstat(var fsetstat):
            out.writeSSHString(&fsetstat.payload.handle)
            out.writeSFTPFileAttributes(fsetstat.payload.attributes)
        case .setstat(let setstat):
            out.writeSSHString(setstat.payload.path)
            out.writeSFTPFileAttributes(setstat.payload.attributes)
        case .symlink(let symlink):
            out.writeSSHString(symlink.payload.linkPath)
            out.writeSSHString(symlink.payload.targetPath)
        case .readlink(let readlink):
            out.writeSSHString(readlink.path)
        }
        let length = out.writerIndex - lengthIndex - 4
        out.setInteger(UInt32(length), at: lengthIndex)
    }
}

private extension SFTPMessage {

    var type: SFTPMessageType {
        switch self {
        case .initialize:
            return .initialize
        case .version:
            return .version
        case .openFile:
            return .openFile
        case .closeFile:
            return .closeFile
        case .read:
            return .read
        case .write:
            return .write
        case .handle:
            return .handle
        case .status:
            return .status
        case .data:
            return .data
        case .mkdir:
            return .mkdir
        case .rmdir:
            return .rmdir
        case .opendir:
            return .opendir
        case .stat:
            return .stat
        case .fstat:
            return .fstat
        case .remove:
            return .remove
        case .fsetstat:
            return .fsetstat
        case .setstat:
            return .setstat
        case .symlink:
            return .symlink
        case .readlink:
            return .readlink
        case .lstat:
            return .lstat
        case .realpath:
            return .realpath
        case .name:
            return .name
        case .attributes:
            return .attributes
        case .readdir:
            return .readdir
        }
    }
}
