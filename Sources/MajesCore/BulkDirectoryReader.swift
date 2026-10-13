import Darwin

public enum DirectoryReadResult: Sendable { case entries([DirEntry]); case failed(errno: Int32) }

public protocol DirectoryReading: Sendable { func read(path: String) -> DirectoryReadResult }

/// Lists one directory with `getattrlistbulk`: names, kinds and physical sizes in a few syscalls.
public struct BulkDirectoryReader: DirectoryReading {
    public init() {}

    public func read(path: String) -> DirectoryReadResult {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 { return .failed(errno: errno) }
        defer { close(fd) }

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_ERROR)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FLAGS) | attrgroup_t(ATTR_CMN_FILEID)
        attrs.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
        attrs.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
        attrs.forkattr = attrgroup_t(ATTR_CMNEXT_CLONEID) | attrgroup_t(ATTR_CMNEXT_CLONE_REFCNT)

        let bufSize = 128 * 1024
        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 16)
        defer { buf.deallocate() }
        var out: [DirEntry] = []

        while true {
            let n = getattrlistbulk(fd, &attrs, buf, bufSize, UInt64(FSOPT_ATTR_CMN_EXTENDED))
            if n < 0 { return .failed(errno: errno) }
            if n == 0 { break }
            var entry = UnsafeRawPointer(buf)
            for _ in 0..<n {
                let length = entry.loadUnaligned(as: UInt32.self)
                if let e = Self.parse(entry) { out.append(e) }
                entry += Int(length)
            }
        }
        return .entries(out)
    }

    /// Layout (verified on macOS 26): length, returned set, ERROR, then requested attrs in bit
    /// order — common, dir (dirs only), file (non-dirs only), extended. Present iff set in `returned`.
    static func parse(_ entry: UnsafeRawPointer) -> DirEntry? {
        var p = entry + 4
        let returned = p.loadUnaligned(as: attribute_set_t.self)
        p += MemoryLayout<attribute_set_t>.size
        func has(_ group: attrgroup_t, _ bit: Int32) -> Bool { group & attrgroup_t(bit) != 0 }

        if has(returned.commonattr, ATTR_CMN_ERROR) {
            if p.loadUnaligned(as: UInt32.self) != 0 { return nil }
            p += 4
        }
        var name = ""
        if has(returned.commonattr, ATTR_CMN_NAME) {
            let off = p.loadUnaligned(as: Int32.self)
            name = String(cString: (p + Int(off)).assumingMemoryBound(to: CChar.self))
            p += MemoryLayout<attrreference_t>.size
        }
        var objType: UInt32 = 0
        if has(returned.commonattr, ATTR_CMN_OBJTYPE) { objType = p.loadUnaligned(as: UInt32.self); p += 4 }
        var flags: UInt32 = 0
        if has(returned.commonattr, ATTR_CMN_FLAGS) { flags = p.loadUnaligned(as: UInt32.self); p += 4 }
        var fileID: UInt64 = 0
        if has(returned.commonattr, ATTR_CMN_FILEID) { fileID = p.loadUnaligned(as: UInt64.self); p += 8 }
        var mountStatus: UInt32 = 0
        if has(returned.dirattr, ATTR_DIR_MOUNTSTATUS) { mountStatus = p.loadUnaligned(as: UInt32.self); p += 4 }
        var linkCount: UInt32 = 1
        if has(returned.fileattr, ATTR_FILE_LINKCOUNT) { linkCount = p.loadUnaligned(as: UInt32.self); p += 4 }
        var allocSize: Int64 = 0
        if has(returned.fileattr, ATTR_FILE_ALLOCSIZE) { allocSize = p.loadUnaligned(as: Int64.self); p += 8 }
        var cloneID: UInt64 = 0
        if has(returned.forkattr, ATTR_CMNEXT_CLONEID) { cloneID = p.loadUnaligned(as: UInt64.self); p += 8 }
        var cloneRefs: UInt32 = 1
        if has(returned.forkattr, ATTR_CMNEXT_CLONE_REFCNT) { cloneRefs = p.loadUnaligned(as: UInt32.self); p += 4 }

        let kind: DirEntry.Kind
        switch objType {
        case UInt32(VREG.rawValue): kind = .file
        case UInt32(VDIR.rawValue): kind = .directory
        case UInt32(VLNK.rawValue): kind = .symlink
        default: kind = .other
        }
        return DirEntry(name: name, kind: kind, allocatedSize: UInt64(max(0, allocSize)), fileID: fileID,
                        linkCount: linkCount, cloneID: cloneID, cloneRefCount: cloneRefs,
                        isMountPoint: mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0,
                        isCompressed: flags & UInt32(UF_COMPRESSED) != 0,
                        isDataless: flags & 0x4000_0000 != 0)  // SF_DATALESS: iCloud placeholder
    }
}
