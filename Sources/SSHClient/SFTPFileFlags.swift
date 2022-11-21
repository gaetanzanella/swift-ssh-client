import Foundation

public struct SFTPOpenFileFlags: OptionSet {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// SSH_FXF_READ
    ///
    /// Open the file for reading.
    public static let read = SFTPOpenFileFlags(rawValue: 0x0000_0001)

    /// SSH_FXF_WRITE
    ///
    /// Open the file for writing.  If both this and SSH_FXF_READ are
    /// specified, the file is opened for both reading and writing.
    public static let write = SFTPOpenFileFlags(rawValue: 0x0000_0002)

    /// SSH_FXF_APPEND
    ///
    /// Force all writes to append data at the end of the file.
    public static let append = SFTPOpenFileFlags(rawValue: 0x0000_0004)

    /// SSH_FXF_CREAT
    ///
    /// If this flag is specified, then a new file will be created if one
    /// does not already exist (if O_TRUNC is specified, the new file will
    /// be truncated to zero length if it previously exists).
    public static let create = SFTPOpenFileFlags(rawValue: 0x0000_0008)

    /// SSH_FXF_TRUNC
    ///
    /// Forces an existing file with the same name to be truncated to zero
    /// length when creating a file by specifying SSH_FXF_CREAT.
    /// SSH_FXF_CREAT MUST also be specified if this flag is used.
    public static let truncate = SFTPOpenFileFlags(rawValue: 0x0000_0010)

    /// SSH_FXF_EXCL
    ///
    /// Causes the request to fail if the named file already exists.
    /// SSH_FXF_CREAT MUST also be specified if this flag is used.
    public static let forceCreate = SFTPOpenFileFlags(rawValue: 0x0000_0020)
}

public struct SFTPFileAttributes: CustomDebugStringConvertible {
    public typealias Permissions = UInt32

    public typealias ExtendedData = [(String, String)]

    public struct Flags: OptionSet {
        public var rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let size = Flags(rawValue: 0x0000_0001)
        public static let uidgid = Flags(rawValue: 0x0000_0002)
        public static let permissions = Flags(rawValue: 0x0000_0004)
        public static let acmodtime = Flags(rawValue: 0x0000_0008)
        public static let extended = Flags(rawValue: 0x8000_0000)
    }

    public struct UserGroupId {
        public let userId: UInt32
        public let groupId: UInt32

        public init(
            userId: UInt32,
            groupId: UInt32
        ) {
            self.userId = userId
            self.groupId = groupId
        }
    }

    public struct AccessModificationTime {
        // Both written as UInt32 seconds since jan 1 1970 as UTC
        public let accessTime: Date
        public let modificationTime: Date

        public init(
            accessTime: Date,
            modificationTime: Date
        ) {
            self.accessTime = accessTime
            self.modificationTime = modificationTime
        }
    }

    public var flags: Flags {
        var flags: Flags = []

        if size != nil {
            flags.insert(.size)
        }

        if uidgid != nil {
            flags.insert(.uidgid)
        }

        if permissions != nil {
            flags.insert(.permissions)
        }

        if accessModificationTime != nil {
            flags.insert(.acmodtime)
        }

        if extended != nil {
            flags.insert(.extended)
        }

        return flags
    }

    public let size: UInt64?
    public let uidgid: UserGroupId?

    // TODO: Permissions as OptionSet
    public let permissions: Permissions?
    public let accessModificationTime: AccessModificationTime?
    public let extended: [(String, String)]?

    public init(size: UInt64? = nil,
                uidgid: UserGroupId? = nil,
                accessModificationTime: AccessModificationTime? = nil,
                permissions: Permissions? = nil,
                extended: [(String, String)]? = nil) {
        self.size = size
        self.uidgid = uidgid
        self.accessModificationTime = accessModificationTime
        self.permissions = permissions
        self.extended = extended
    }

    public static let none = SFTPFileAttributes()

    public var debugDescription: String { "{perm: \(permissions ?? 0), size: \(size ?? 0)" }
}
