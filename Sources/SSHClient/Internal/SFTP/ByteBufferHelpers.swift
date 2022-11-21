import Foundation
import NIO

extension ByteBuffer {
    mutating func writeSFTPDate(_ date: Date) {
        writeInteger(UInt32(date.timeIntervalSince1970))
    }

    mutating func readSFTPDate() -> Date? {
        guard let date = readInteger(as: UInt32.self) else {
            return nil
        }

        return Date(timeIntervalSince1970: TimeInterval(date))
    }

    mutating func writeSFTPFileAttributes(_ attributes: SFTPFileAttributes) {
        writeInteger(attributes.flags.rawValue)

        if let size = attributes.size {
            writeInteger(size)
        }

        if let uidgid = attributes.uidgid {
            writeInteger(uidgid.userId)
            writeInteger(uidgid.groupId)
        }

        if let permissions = attributes.permissions {
            writeInteger(permissions)
        }

        if let accessModificationTime = attributes.accessModificationTime {
            writeSFTPDate(accessModificationTime.accessTime)
            writeSFTPDate(accessModificationTime.modificationTime)
        }

        for (key, value) in attributes.extended ?? [] {
            writeSSHString(key)
            writeSSHString(value)
        }
    }

    mutating func readSFTPFileAttributes() -> SFTPFileAttributes? {
        guard let _flags = readInteger(as: UInt32.self) else {
            return nil
        }
        let flags = SFTPFileAttributes.Flags(rawValue: _flags)
        var attributesSize: UInt64?
        var attributesGroupId: SFTPFileAttributes.UserGroupId?
        var attributesPermissions: SFTPFileAttributes.Permissions?
        var attributesModificationDates: SFTPFileAttributes.AccessModificationTime?
        var attributesExtendedData: SFTPFileAttributes.ExtendedData?
        if flags.contains(.size) {
            guard let size = readInteger(as: UInt64.self) else {
                return nil
            }
            attributesSize = size
        }
        if flags.contains(.uidgid) {
            guard
                let uid = readInteger(as: UInt32.self),
                let gid = readInteger(as: UInt32.self)
            else {
                return nil
            }
            attributesGroupId = .init(
                userId: uid,
                groupId: gid
            )
        }
        if flags.contains(.permissions) {
            guard let permissions = readInteger(as: UInt32.self) else {
                return nil
            }
            attributesPermissions = permissions
        }
        if flags.contains(.acmodtime) {
            guard
                let accessTime = readSFTPDate(),
                let modificationTime = readSFTPDate()
            else {
                return nil
            }
            attributesModificationDates = .init(
                accessTime: accessTime,
                modificationTime: modificationTime
            )
        }
        if flags.contains(.extended) {
            guard let extendedCount = readInteger(as: UInt32.self) else {
                return nil
            }
            attributesExtendedData = []
            for _ in 0 ..< extendedCount {
                guard
                    let type = readSSHString(),
                    let data = readSSHString()
                else {
                    return nil
                }
                attributesExtendedData?.append((type, data))
            }
        }
        return SFTPFileAttributes(
            size: attributesSize,
            uidgid: attributesGroupId,
            accessModificationTime: attributesModificationDates,
            permissions: attributesPermissions,
            extended: attributesExtendedData
        )
    }

    mutating func writeSSHString(_ buffer: inout ByteBuffer) {
        writeInteger(UInt32(buffer.readableBytes))
        writeBuffer(&buffer)
    }

    mutating func writeSSHString(_ string: String) {
        let oldWriterIndex = writerIndex
        moveWriterIndex(forwardBy: 4)
        writeString(string)
        setInteger(UInt32(writerIndex - oldWriterIndex - 4), at: oldWriterIndex)
    }

    mutating func readSSHString() -> String? {
        guard
            let length = getInteger(at: readerIndex, as: UInt32.self),
            let string = getString(at: readerIndex + 4, length: Int(length))
        else {
            return nil
        }

        moveReaderIndex(forwardBy: 4 + Int(length))
        return string
    }

    mutating func readSSHBuffer() -> ByteBuffer? {
        guard
            let length = getInteger(at: readerIndex, as: UInt32.self),
            let slice = getSlice(at: readerIndex + 4, length: Int(length))
        else {
            return nil
        }

        moveReaderIndex(forwardBy: 4 + Int(length))
        return slice
    }
}
