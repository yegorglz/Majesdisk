public struct HiddenSpaceBreakdown: Sendable, Equatable {
    public var purgeable: UInt64
    public var otherVolumes: UInt64
    public var stillHidden: UInt64
    public var total: UInt64 { purgeable + otherVolumes + stillHidden }
    public init(purgeable: UInt64, otherVolumes: UInt64, stillHidden: UInt64) {
        self.purgeable = purgeable; self.otherVolumes = otherVolumes; self.stillHidden = stillHidden
    }
}

/// Space the volume reports as used that no scanned file accounts for.
public enum HiddenSpace {
    public static func compute(usedBytes: UInt64, scannedBytes: UInt64, purgeableBytes: UInt64, otherVolumesBytes: UInt64) -> HiddenSpaceBreakdown? {
        guard usedBytes > scannedBytes else { return nil }
        let hidden = usedBytes - scannedBytes
        let purgeable = min(purgeableBytes, hidden)
        let other = min(otherVolumesBytes, hidden - purgeable)
        return HiddenSpaceBreakdown(purgeable: purgeable, otherVolumes: other, stillHidden: hidden - purgeable - other)
    }

    public static func attach(_ b: HiddenSpaceBreakdown, to tree: FileTree) {
        let h = tree.appendVirtual(parent: tree.root, name: "Hidden space", size: 0, kind: .hiddenSpace)
        for (name, size, kind) in [("Purgeable space", b.purgeable, VirtualKind.purgeable),
                                   ("Other volumes", b.otherVolumes, .otherVolumes),
                                   ("Still hidden", b.stillHidden, .stillHidden)] where size > 0 {
            tree.appendVirtual(parent: h, name: name, size: size, kind: kind)
        }
    }
}
