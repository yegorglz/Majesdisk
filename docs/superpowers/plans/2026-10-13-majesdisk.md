# MajesDisk (DaisyDisk Recreation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build MajesDisk, a native macOS disk-space analyzer that matches DaisyDisk 4 standalone: disks overview, fast parallel physical-size scanner, interactive sunburst map, Quick Look, Collector with safe deletion, hidden/purgeable space, Full Disk Access guidance, and Scan/Delete as Administrator.

**Architecture:** A SwiftPM package with two pure libraries, `MajesCore` (file system, tree, scanning, volumes, deletion, privileges) and `MajesMap` (sunburst geometry, palette, transitions, history, key bindings). Both are unit-tested with Swift Testing. On top sit two executables: `MajesDisk` (SwiftUI + AppKit app) and `majes-helper` (CLI run as root through `osascript` for admin scans and deletes). `scripts/build-app.sh` assembles and codesigns `dist/MajesDisk.app` without Xcode. The file tree is an index arena (`NodeID = Int32`, parallel arrays) built under a lock by N `getattrlistbulk` worker threads.

**Tech Stack:** Swift 6.3 toolchain (language mode 5), SwiftPM, SwiftUI + AppKit (NSView rendering with Core Graphics), QuickLookUI, Darwin `getattrlistbulk`, Swift Testing, `diskutil`/`tmutil`/`osascript` via `Process`.

**Spec:** `docs/superpowers/specs/2026-10-13-majesdisk-design.md` (research findings §1, requirements R1–R12 §2, out of scope §3).

**Execution in a few prompts:** three milestones, one prompt each. Every milestone ends with green tests and a launchable app.
- **Prompt 1, Milestone A (Engine):** Tasks 1–6
- **Prompt 2, Milestone B (Map and browsing UI):** Tasks 7–12
- **Prompt 3, Milestone C (Cleanup and privileges):** Tasks 13–18

## Global Constraints

- Project root: `/Users/yegor/ClaudeProjects/MajesDisk`. All paths below are relative to it.
- No Xcode. Build with `swift build`. Test **only** through `scripts/test.sh` (it adds the Command Line Tools `Testing.framework` search paths). Tests use `import Testing` (`@Test`, `#expect`), never XCTest. XCTest is not available.
- `Package.swift`: `// swift-tools-version:6.0`, `platforms: [.macOS(.v14)]`, `swiftLanguageModes: [.v5]`. No third-party dependencies.
- Product name **MajesDisk**, bundle ID `com.majesdisk.MajesDisk`, helper binary `majes-helper` at `MajesDisk.app/Contents/Helpers/majes-helper`. The string "DaisyDisk" never appears in UI, bundle, or code identifiers.
- Not sandboxed, no entitlements file. Hardened runtime (`codesign --options runtime`). Signing identity from `$MAJESDISK_SIGN_IDENTITY`, default ad-hoc `-`.
- All sizes are physical allocated bytes (`ATTR_FILE_ALLOCSIZE`), `UInt64`. User-facing sizes format through `ByteFormat.string(_:locale:)` (`.byteCount(style: .file)`, decimal like Finder, in the user's locale). Tests always pass `Locale(identifier: "en_US")`.
- Children are always ordered by size descending, then name ascending (`localizedStandardCompare`).
- Deletion default is **permanent** (`FileManager.removeItem`) after a **5-second** cancelable countdown. Setting `deleteMode` = `.moveToTrash` is the alternative. `ProtectedPaths.verdict` is checked in the UI, in `Deleter`, **and** in `majes-helper delete`.
- Elevation is per-action via `/usr/bin/osascript … with administrator privileges`. No launchd daemon is installed. No network access and no telemetry.
- Map constants: 6 rings (`maxDepth = 6`), center radius 0.22 of outer radius, `minSegmentAngle = 0.0105` rad (0.6°), transition 0.3 s.
- Gauge thresholds: used fraction ≤ 0.50 green, ≤ 0.85 orange, else red. Overview refresh every 2 s.

## Review Focus

1. **Scanning `/` on a modern APFS system:** must not double count (Data volume via firmlinks *and* `/System/Volumes/Data`), must not descend `/dev` or `/Volumes/*` mounts, and must finish. The expected total is close to the Data+System volume `CapacityInUse`. Pinned by `scannerDoesNotDescendMountPoints` (Task 4) and the Task 18 real-disk check.
2. **Permission-denied folders mid-tree:** the scan continues, the folder is flagged restricted, and its siblings are counted. Pinned by `readerReportsPermissionDenied` (Task 3) and `scannerFlagsRestrictedAndContinues` (Task 4).
3. **Deleting the wrong thing:** a symlink to a folder deletes only the link. A protected path is refused even if the UI lets it through. A path that vanished since the scan reports `.notFound` without crashing. Pinned by `deleterRemovesSymlinkNotTarget`, `deleterRefusesProtectedPath`, `deleterReportsMissing` (Task 13) and `helperDeleteRefusesProtected` (Task 16).
4. **Degenerate trees:** empty folder, root size 0, a single huge file, 5,000+ entries in one folder, Unicode/emoji and very long names. Expected: no divide-by-zero and no blank map crash, and the buffer loop reads everything. Pinned by `layoutOfEmptyRootIsEmpty` and `singleChildFillsFullCircle` (Task 7), `readerReadsLargeDirectory` and `readerHandlesUnicodeNames` (Task 3).
5. **Cancel mid-scan / quitting during an admin scan:** worker threads exit promptly, `run` returns nil, and the root helper stops when the cancel file appears. Pinned by `scannerCancelsPromptly` (Task 4) and `helperScanHonorsCancelFile` (Task 6).

---

# Milestone A — Engine (Prompt 1)

### Task 1: Package scaffold, tooling, ByteFormat

**Files:**
- Create: `Package.swift`, `.gitignore`, `scripts/test.sh`, `Sources/MajesCore/ByteFormat.swift`, `Sources/MajesMap/MajesMap.swift` (placeholder `public enum MajesMap {}`), `Sources/MajesDisk/main.swift` (temporary `print("MajesDisk")`, replaced in Task 8), `Sources/majes-helper/main.swift` (temporary, replaced in Task 6), `Tests/MajesCoreTests/ByteFormatTests.swift`, `Tests/MajesMapTests/SmokeTests.swift`

**Interfaces:**
- Produces: `public enum ByteFormat { public static func string(_ bytes: UInt64, locale: Locale = .current) -> String }`. Products `MajesCore`, `MajesMap`, executables `MajesDisk`, `majes-helper`.

- [ ] **Step 1: `git init` in the project root and write `Package.swift` exactly:**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MajesDisk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MajesDisk", targets: ["MajesDisk"]),
        .executable(name: "majes-helper", targets: ["majes-helper"]),
    ],
    targets: [
        .target(name: "MajesCore"),
        .target(name: "MajesMap", dependencies: ["MajesCore"]),
        .executableTarget(name: "MajesDisk", dependencies: ["MajesCore", "MajesMap"]),
        .executableTarget(name: "majes-helper", dependencies: ["MajesCore"]),
        .testTarget(name: "MajesCoreTests", dependencies: ["MajesCore"]),
        .testTarget(name: "MajesMapTests", dependencies: ["MajesMap", "MajesCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Write `scripts/test.sh` exactly (chmod +x). Swift Testing needs these flags under Command Line Tools:**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if xcode-select -p | grep -q CommandLineTools; then
  F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  exec swift test -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" \
    -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
else
  exec swift test "$@"
fi
```

`.gitignore`: `.build/`, `dist/`, `*.iconset/`, `.DS_Store`.

- [ ] **Step 3: Write the failing test** `Tests/MajesCoreTests/ByteFormatTests.swift`:

```swift
import Testing
@testable import MajesCore

@Test func formatsDecimalLikeFinder() {
    let en = Locale(identifier: "en_US")
    #expect(ByteFormat.string(0, locale: en) == "Zero kB")
    #expect(ByteFormat.string(1_500_000_000, locale: en) == "1.5 GB")
    #expect(ByteFormat.string(52_428_800, locale: en) == "52.4 MB")
    #expect(ByteFormat.string(1_500_000_000, locale: Locale(identifier: "de_DE")) == "1,5 GB")
}
```
`SmokeTests.swift`: `@Test func mapModuleLinks() { _ = MajesMap.self }`.

- [ ] **Step 4: Run `scripts/test.sh`.** Expected: FAIL, `ByteFormat` not found.
- [ ] **Step 5: Implement `ByteFormat.string`** as `Int64(clamping: bytes).formatted(.byteCount(style: .file).locale(locale))`. Verified on this Mac: en_US gives "1.5 GB" and "Zero kB".
- [ ] **Step 6: Run `scripts/test.sh` and `swift build`.** Expected: 2 tests pass, build succeeds.
- [ ] **Step 7: Commit** `git add -A && git commit -m "chore: scaffold MajesDisk package, test script, ByteFormat"`

---

### Task 2: FileTree arena + builder (with link/clone dedupe)

**Files:**
- Create: `Sources/MajesCore/DirEntry.swift`, `Sources/MajesCore/FileTree.swift`, `Sources/MajesCore/FileTreeBuilder.swift`
- Test: `Tests/MajesCoreTests/FileTreeTests.swift`

**Interfaces:**
- Produces:
```swift
public typealias NodeID = Int32
public struct DirEntry: Sendable, Equatable {
    public enum Kind: UInt8, Sendable { case file, directory, symlink, other }
    public var name: String; public var kind: Kind; public var allocatedSize: UInt64
    public var fileID: UInt64; public var linkCount: UInt32; public var cloneID: UInt64; public var cloneRefCount: UInt32
    public var isMountPoint: Bool; public var isCompressed: Bool; public var isDataless: Bool
    public init(name: String, kind: Kind, allocatedSize: UInt64 = 0, fileID: UInt64 = 0, linkCount: UInt32 = 1,
                cloneID: UInt64 = 0, cloneRefCount: UInt32 = 1, isMountPoint: Bool = false,
                isCompressed: Bool = false, isDataless: Bool = false)
}
public struct NodeFlags: OptionSet, Sendable { public let rawValue: UInt16
    // directory=1<<0 package=1<<1 symlink=1<<2 restricted=1<<3 secondaryLink=1<<4 deleted=1<<5 virtual=1<<6 mountPoint=1<<7 dataless=1<<8
}
public enum VirtualKind: UInt8, Sendable { case hiddenSpace, purgeable, otherVolumes, stillHidden }
public final class FileTree: @unchecked Sendable {
    public let rootPath: String
    public var root: NodeID { 0 }
    public var nodeCount: Int { get }
    public func name(_ id: NodeID) -> String
    public func size(_ id: NodeID) -> UInt64          // aggregated for directories
    public func itemCount(_ id: NodeID) -> Int        // files+folders beneath, inclusive of self for files
    public func flags(_ id: NodeID) -> NodeFlags
    public func parent(_ id: NodeID) -> NodeID?       // nil for root
    public func children(_ id: NodeID) -> [NodeID]    // excludes .deleted, sorted per Global Constraints
    public func path(_ id: NodeID) -> String          // rootPath + "/" + names; root -> rootPath
    public func node(atPath: String) -> NodeID?
    public func virtualKind(_ id: NodeID) -> VirtualKind?
    public func isAncestor(_ a: NodeID, of b: NodeID) -> Bool
    public func markDeleted(_ id: NodeID)             // MainActor use only
    public func appendVirtual(parent: NodeID, name: String, size: UInt64, kind: VirtualKind) -> NodeID
}
public final class FileTreeBuilder {
    public init(rootPath: String)
    public var root: NodeID { 0 }
    public func markRestricted(_ id: NodeID)
    @discardableResult public func appendChildren(of parent: NodeID, entries: [DirEntry]) -> [NodeID]
    public func finish() -> FileTree
}
```

Storage is parallel arrays indexed by `NodeID`: `names [String]`, `parents [NodeID]` (-1 for root), `sizes [UInt64]`, `itemCounts [Int32]`, `flags [NodeFlags]`, `childIDs [[NodeID]]`, plus a `[NodeID: VirtualKind]` dictionary. IDs never move. Sorting reorders only the `childIDs` lists.

- [ ] **Step 1: Write the failing tests** in `FileTreeTests.swift`:

```swift
import Testing
@testable import MajesCore

private func sample() -> FileTree {
    let b = FileTreeBuilder(rootPath: "/r")
    let top = b.appendChildren(of: b.root, entries: [
        DirEntry(name: "a", kind: .directory),
        DirEntry(name: "f", kind: .file, allocatedSize: 100),
        DirEntry(name: "e", kind: .directory)])
    b.appendChildren(of: top[0], entries: [DirEntry(name: "g", kind: .file, allocatedSize: 300)])
    return b.finish()
}

@Test func aggregatesAndSorts() {
    let t = sample()
    #expect(t.size(t.root) == 400)
    #expect(t.children(t.root).map(t.name) == ["a", "f", "e"])
    #expect(t.path(t.children(t.root)[0]) == "/r/a")
    #expect(t.itemCount(t.root) == 4)
    #expect(t.node(atPath: "/r/a/g").map(t.size) == 300)
}

@Test func hardLinksAndClonesCountOnce() {
    let b = FileTreeBuilder(rootPath: "/r")
    let ids = b.appendChildren(of: b.root, entries: [
        DirEntry(name: "a", kind: .file, allocatedSize: 1000, fileID: 7, linkCount: 2, cloneID: 7, cloneRefCount: 2),
        DirEntry(name: "h", kind: .file, allocatedSize: 1000, fileID: 7, linkCount: 2, cloneID: 7, cloneRefCount: 2),
        DirEntry(name: "b", kind: .file, allocatedSize: 1000, fileID: 8, linkCount: 1, cloneID: 7, cloneRefCount: 2)])
    let t = b.finish()
    #expect(t.size(t.root) == 1000)
    #expect(ids.filter { t.flags($0).contains(.secondaryLink) }.count == 2)
}

@Test func markDeletedUpdatesAncestorsAndResorts() {
    let t = sample()
    let a = t.node(atPath: "/r/a")!
    t.markDeleted(t.node(atPath: "/r/a/g")!)
    #expect(t.size(t.root) == 100)
    #expect(t.size(a) == 0)
    #expect(t.children(t.root).map(t.name) == ["f", "a", "e"])
}

@Test func virtualNodesAddToParent() {
    let t = sample()
    let h = t.appendVirtual(parent: t.root, name: "Hidden space", size: 600, kind: .hiddenSpace)
    #expect(t.size(t.root) == 1000)
    #expect(t.children(t.root).first == h)
    #expect(t.virtualKind(h) == .hiddenSpace)
}
```

- [ ] **Step 2: Run `scripts/test.sh --filter FileTreeTests`.** Expected: FAIL, types undefined.
- [ ] **Step 3: Implement `DirEntry`, `NodeFlags`, `VirtualKind`, `FileTree`, `FileTreeBuilder`.** The builder's dedupe: a file whose `linkCount > 1 || cloneRefCount > 1` uses key `cloneID != 0 ? cloneID : fileID`. The first key seen keeps its size; later ones get size 0 and `.secondaryLink`. `finish()` does one post-order pass (iterate IDs descending, because children always have larger IDs than parents) to sum sizes and item counts, then sorts every `childIDs` list. `markDeleted` subtracts the node's size and item count from every ancestor, sets `.deleted`, and re-sorts the child list of each ancestor's parent. `appendVirtual` adds size up the chain, sets `.virtual`, and re-sorts the same way.
- [ ] **Step 4: Run `scripts/test.sh --filter FileTreeTests`.** Expected: 4 pass.
- [ ] **Step 5: Commit** `git commit -am "feat(core): FileTree arena with link/clone dedupe"` (add new files first).

---

### Task 3: BulkDirectoryReader (getattrlistbulk)

**Files:**
- Create: `Sources/MajesCore/BulkDirectoryReader.swift`
- Test: `Tests/MajesCoreTests/BulkDirectoryReaderTests.swift`, `Tests/MajesCoreTests/Fixtures.swift` (temp-dir helper `makeTempDir() -> String`, `write(_ path: String, bytes: Int)`, `allocated(_ path: String) -> UInt64` = `lstat` `st_blocks * 512`)

**Interfaces:**
- Consumes: `DirEntry` (Task 2).
- Produces:
```swift
public enum DirectoryReadResult: Sendable { case entries([DirEntry]); case failed(errno: Int32) }
public protocol DirectoryReading: Sendable { func read(path: String) -> DirectoryReadResult }
public struct BulkDirectoryReader: DirectoryReading { public init(); public func read(path: String) -> DirectoryReadResult }
```

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func readerReportsKindsSizesLinksAndClones() throws {
    let d = makeTempDir()
    write("\(d)/big", bytes: 1_000_000)
    try FileManager.default.createDirectory(atPath: "\(d)/sub", withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(atPath: "\(d)/link", withDestinationPath: "\(d)/sub")
    #expect(link("\(d)/big", "\(d)/hard") == 0)
    #expect(clonefile("\(d)/big", "\(d)/clone", 0) == 0)
    guard case .entries(let es) = BulkDirectoryReader().read(path: d) else { Issue.record("failed"); return }
    let by = Dictionary(uniqueKeysWithValues: es.map { ($0.name, $0) })
    #expect(Set(by.keys) == ["big", "sub", "link", "hard", "clone"])
    #expect(by["sub"]?.kind == .directory && by["link"]?.kind == .symlink)
    #expect(by["big"]?.allocatedSize == allocated("\(d)/big"))
    #expect(by["big"]?.linkCount == 2 && by["hard"]?.fileID == by["big"]?.fileID)
    #expect(by["clone"]?.cloneID == by["big"]?.cloneID && by["clone"]!.cloneRefCount >= 2)
    #expect(by["sub"]?.isMountPoint == false)
}

@Test func readerReadsLargeDirectory() {
    let d = makeTempDir()
    for i in 0..<5_000 { write("\(d)/file-with-a-fairly-long-name-\(i).txt", bytes: 1) }
    guard case .entries(let es) = BulkDirectoryReader().read(path: d) else { Issue.record("failed"); return }
    #expect(es.count == 5_000)
}

@Test func readerHandlesUnicodeNames() {
    let d = makeTempDir(); let name = "Фото 🌼 café " + String(repeating: "x", count: 200)
    write("\(d)/\(name)", bytes: 10)
    guard case .entries(let es) = BulkDirectoryReader().read(path: d) else { Issue.record("failed"); return }
    #expect(es.map(\.name) == [name])
}

@Test func readerReportsPermissionDenied() {
    let d = makeTempDir(); mkdir("\(d)/locked", 0o000); defer { chmod("\(d)/locked", 0o755) }
    guard getuid() != 0 else { return }
    guard case .failed(let e) = BulkDirectoryReader().read(path: "\(d)/locked") else { Issue.record("expected failure"); return }
    #expect(e == EACCES)
}

@Test func readerReportsMissing() {
    guard case .failed(let e) = BulkDirectoryReader().read(path: "/nonexistent-\(UUID())") else { Issue.record("x"); return }
    #expect(e == ENOENT)
}

@Test func mountPointsAreFlagged() {   // live system check
    guard case .entries(let es) = BulkDirectoryReader().read(path: "/") else { Issue.record("x"); return }
    #expect(es.first { $0.name == "dev" }?.isMountPoint == true)
    #expect(es.first { $0.name == "Users" }?.isMountPoint == false)
}
```
Compare names after NFC normalization if the file system returns NFD (`precomposedStringWithCanonicalMapping` on both sides).

- [ ] **Step 2: Run `scripts/test.sh --filter BulkDirectoryReaderTests`.** Expected: FAIL.
- [ ] **Step 3: Implement `BulkDirectoryReader.read(path:)`** with these decisions:
  - `open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)`. On failure return `.failed(errno)`. Loop `getattrlistbulk` into a 128 KiB buffer until it returns 0, and `.failed(errno)` on −1.
  - `attrlist`: `commonattr = RETURNED_ATTRS | NAME | ERROR | OBJTYPE | FLAGS | FILEID`, `dirattr = ATTR_DIR_MOUNTSTATUS`, `fileattr = ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE`, `forkattr = ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_CLONE_REFCNT`. Options `FSOPT_ATTR_CMN_EXTENDED`, and **no** `FSOPT_PACK_INVAL_ATTRS`.
  - Parse each entry with a cursor in this order, advancing only for bits set in `returned`: length u32 → `attribute_set_t` → ERROR u32 → NAME (`attrreference_t`, string at `fieldStart + attr_dataoffset`) → OBJTYPE u32 → FLAGS u32 → FILEID u64 → (dirs) MOUNTSTATUS u32 → (non-dirs) LINKCOUNT u32, ALLOCSIZE off_t → CLONEID u64, CLONE_REFCNT u32. Use `UnsafeRawPointer.loadUnaligned`. Jump to `entryStart + length` after each entry. Skip entries whose ERROR ≠ 0.
  - Map `VREG → .file`, `VDIR → .directory`, `VLNK → .symlink`, others → `.other`. `isMountPoint = mountstatus & DIR_MNTSTATUS_MNTPOINT != 0`. `isCompressed = flags & UF_COMPRESSED`, `isDataless = flags & SF_DATALESS (0x40000000)`. Symlinks keep their own allocated size and are never followed.
- [ ] **Step 4: Run the filter again.** Expected: 6 pass.
- [ ] **Step 5: Commit** `feat(core): getattrlistbulk directory reader`

---

### Task 4: Parallel Scanner

**Files:**
- Create: `Sources/MajesCore/Scanner.swift`, `Sources/MajesCore/PackageExtensions.swift`
- Test: `Tests/MajesCoreTests/ScannerTests.swift`

**Interfaces:**
- Consumes: `DirectoryReading`, `FileTreeBuilder`, `FileTree` (Tasks 2–3).
- Produces:
```swift
public struct ScanProgress: Sendable, Equatable { public var files: Int; public var directories: Int; public var bytes: UInt64; public var currentPath: String }
public struct ScanOptions: Sendable {
    public var rootPath: String; public var maxConcurrency: Int
    public init(rootPath: String, maxConcurrency: Int = 8)
    public static func recommendedConcurrency(isSolidState: Bool?) -> Int   // false -> 1, else 8
}
public final class Scanner: @unchecked Sendable {
    public init(options: ScanOptions, reader: DirectoryReading = BulkDirectoryReader())
    /// Blocking; call off the main thread. Returns nil when cancelled.
    public func run(progress: @escaping @Sendable (ScanProgress) -> Void = { _ in },
                    isCancelled: @escaping @Sendable () -> Bool = { false }) -> FileTree?
}
public enum PackageExtensions { public static func isPackage(name: String) -> Bool }
```

- [ ] **Step 1: Write the failing tests.** `FakeReader` is a `final class` with a lock-guarded `[String: DirectoryReadResult]` map, a `requested: [String]` log, and an optional per-read `delay`:

```swift
@Test func scannerBuildsTreeFromReader() {
    let r = FakeReader(["/r": .entries([.init(name: "d", kind: .directory), .init(name: "f", kind: .file, allocatedSize: 10)]),
                        "/r/d": .entries([.init(name: "g", kind: .file, allocatedSize: 5)])])
    let t = Scanner(options: .init(rootPath: "/r", maxConcurrency: 4), reader: r).run()!
    #expect(t.size(t.root) == 15)
    #expect(t.children(t.root).map(t.name) == ["f", "d"])
}

@Test func scannerDoesNotDescendMountPointsOrSymlinks() {
    let r = FakeReader(["/r": .entries([.init(name: "dev", kind: .directory, isMountPoint: true),
                                        .init(name: "l", kind: .symlink, allocatedSize: 4096)])])
    let t = Scanner(options: .init(rootPath: "/r"), reader: r).run()!
    #expect(r.requested == ["/r"])
    #expect(t.flags(t.node(atPath: "/r/dev")!).contains(.mountPoint))
}

@Test func scannerFlagsRestrictedAndContinues() {
    let r = FakeReader(["/r": .entries([.init(name: "x", kind: .directory), .init(name: "f", kind: .file, allocatedSize: 7)]),
                        "/r/x": .failed(errno: EACCES)])
    let t = Scanner(options: .init(rootPath: "/r"), reader: r).run()!
    #expect(t.flags(t.node(atPath: "/r/x")!).contains(.restricted))
    #expect(t.size(t.root) == 7)
}

@Test func scannerCancelsPromptly() {
    var dirs: [String: DirectoryReadResult] = ["/r": .entries((0..<200).map { .init(name: "d\($0)", kind: .directory) })]
    for i in 0..<200 { dirs["/r/d\(i)"] = .entries([]) }
    let r = FakeReader(dirs, delay: 0.01)
    let flag = ManagedAtomicFlag()                        // tiny lock-backed Bool in the test file
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { flag.set() }
    let start = Date()
    #expect(Scanner(options: .init(rootPath: "/r", maxConcurrency: 2), reader: r).run(isCancelled: { flag.value }) == nil)
    #expect(Date().timeIntervalSince(start) < 0.5)
}

@Test func scannerMatchesDiskOnRealFolder() throws {
    let d = makeTempDir(); write("\(d)/a", bytes: 50_000)
    try FileManager.default.createDirectory(atPath: "\(d)/s/t", withIntermediateDirectories: true)
    write("\(d)/s/t/b", bytes: 9_000); link("\(d)/a", "\(d)/s/a-hard")
    let t = Scanner(options: .init(rootPath: d)).run()!
    #expect(t.size(t.root) == allocated("\(d)/a") + allocated("\(d)/s/t/b"))
}

@Test func packagesAreFlagged() {
    #expect(PackageExtensions.isPackage(name: "Safari.app"))
    #expect(PackageExtensions.isPackage(name: "Photos Library.photoslibrary"))
    #expect(!PackageExtensions.isPackage(name: "src"))
}
```

- [ ] **Step 2: Run `scripts/test.sh --filter ScannerTests`.** Expected: FAIL.
- [ ] **Step 3: Implement.** The `PackageExtensions` set (lowercased compare): `app bundle framework plugin appex kext xpc photoslibrary photolibrary musiclibrary tvlibrary imovielibrary fcpbundle logicx band xcodeproj xcworkspace xcarchive playground rtfd pages numbers key mdimporter qlgenerator prefpane saver component vst vst3 aaxplugin dsym`. `Scanner.run` worker pool, the one algorithm the tests do not pin down:

```
state under one NSCondition `cv`: stack: [(NodeID, String)] = [(root, rootPath)], inFlight = 0, progress counters
DispatchQueue.concurrentPerform(iterations: maxConcurrency) { _ in
  loop {
    cv.lock()
    while stack.isEmpty && inFlight > 0 && !isCancelled() { cv.wait(until: now + 0.05) }
    if stack.isEmpty || isCancelled() { cv.broadcast(); cv.unlock(); return }
    let job = stack.removeLast(); inFlight += 1; cv.unlock()
    let result = reader.read(path: job.path)                 // syscalls outside the lock
    cv.lock()
    switch result: .failed -> builder.markRestricted(job.id)
                   .entries(es) -> ids = builder.appendChildren(of: job.id, entries: es)
                                   push (id, job.path + "/" + name) for every .directory entry that is not a mount point
                                   (root path "/" joins without a double slash)
    update counters; inFlight -= 1; cv.broadcast(); cv.unlock()
    emit progress outside the lock if ≥100 ms since the last emit (timestamp kept under the lock)
  }
}
return isCancelled() ? nil : builder.finish()
```
`appendChildren` sets `.directory`, `.package` (via `isPackage`), `.symlink`, `.mountPoint`, and `.dataless` from each entry.

- [ ] **Step 4: Run the filter.** Expected: 6 pass. Then run the full `scripts/test.sh`.
- [ ] **Step 5: Commit** `feat(core): parallel scanner with mount-point, restricted, package handling`

---

### Task 5: Volumes, APFS info, hidden space

**Files:**
- Create: `Sources/MajesCore/Volumes.swift`, `Sources/MajesCore/APFSInfo.swift`, `Sources/MajesCore/HiddenSpace.swift`
- Test: `Tests/MajesCoreTests/VolumesTests.swift`, `Tests/MajesCoreTests/HiddenSpaceTests.swift`

**Interfaces:**
- Consumes: `FileTree.appendVirtual` (Task 2).
- Produces:
```swift
public struct VolumeInfo: Identifiable, Sendable, Equatable {
    public var id: String { mountPath }
    public var name: String; public var mountPath: String; public var fileSystem: String
    public var totalBytes: UInt64; public var availableBytes: UInt64; public var availableImportantBytes: UInt64
    public var isRootFileSystem: Bool; public var isInternal: Bool; public var isRemovable: Bool; public var isLocal: Bool
    public var usedBytes: UInt64 { get }          // total - available (saturating)
    public var purgeableBytes: UInt64 { get }     // max(0, important - available)
    public func usedFraction(purgeableAsUsed: Bool) -> Double   // false: (used - purgeable)/total
}
public enum GaugeLevel: Sendable { case green, orange, red; public static func forFraction(_ f: Double) -> GaugeLevel }
public enum VolumeLister {
    public static func mountedVolumes() -> [VolumeInfo]   // FileManager.mountedVolumeURLs(..., options: [.skipHiddenVolumes])
    public static func sorted(_ v: [VolumeInfo]) -> [VolumeInfo]   // root first, then internal, then name
}
public struct APFSVolumeRecord: Sendable, Equatable { public var name: String; public var deviceIdentifier: String; public var roles: [String]; public var capacityInUse: UInt64 }
public struct APFSContainerRecord: Sendable, Equatable { public var reference: String; public var volumes: [APFSVolumeRecord] }
public struct DiskInfoRecord: Sendable, Equatable { public var deviceIdentifier: String; public var containerReference: String?; public var isSolidState: Bool? }
public enum APFSInfo {
    public static func parseContainers(_ plist: Data) throws -> [APFSContainerRecord]
    public static func parseDiskInfo(_ plist: Data) throws -> DiskInfoRecord
    public static func otherVolumesBytes(containers: [APFSContainerRecord], scanned: DiskInfoRecord, isRootScan: Bool) -> UInt64
    public static func diskInfo(mountPath: String) -> DiskInfoRecord?        // /usr/sbin/diskutil info -plist <path>
    public static func containers() -> [APFSContainerRecord]                  // /usr/sbin/diskutil apfs list -plist
}
public struct HiddenSpaceBreakdown: Sendable, Equatable { public var purgeable: UInt64; public var otherVolumes: UInt64; public var stillHidden: UInt64; public var total: UInt64 { get } }
public enum HiddenSpace {
    public static func compute(usedBytes: UInt64, scannedBytes: UInt64, purgeableBytes: UInt64, otherVolumesBytes: UInt64) -> HiddenSpaceBreakdown?
    public static func attach(_ b: HiddenSpaceBreakdown, to tree: FileTree)   // "Hidden space" > "Purgeable space", "Other volumes", "Still hidden" (zero parts omitted)
}
```

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func hiddenSpaceSplitsRemainder() {
    let b = HiddenSpace.compute(usedBytes: 100, scannedBytes: 60, purgeableBytes: 25, otherVolumesBytes: 10)!
    #expect(b == HiddenSpaceBreakdown(purgeable: 25, otherVolumes: 10, stillHidden: 5))
    #expect(HiddenSpace.compute(usedBytes: 100, scannedBytes: 100, purgeableBytes: 5, otherVolumesBytes: 5) == nil)
    let c = HiddenSpace.compute(usedBytes: 100, scannedBytes: 90, purgeableBytes: 25, otherVolumesBytes: 10)!
    #expect(c == HiddenSpaceBreakdown(purgeable: 10, otherVolumes: 0, stillHidden: 0))   // capped to the remainder
}

@Test func attachBuildsVirtualSubtree() { /* sample tree of 400; attach (25,10,5); root == 440; "Hidden space" child has 3 virtual children with kinds .purgeable/.otherVolumes/.stillHidden */ }

@Test func otherVolumesExcludesSystemAndDataForRootScan() throws {
    let plist = try PropertyListSerialization.data(fromPropertyList: ["Containers": [["ContainerReference": "disk3", "Volumes": [
        ["Name": "Macintosh HD", "DeviceIdentifier": "disk3s1", "Roles": ["System"], "CapacityInUse": 12],
        ["Name": "Data", "DeviceIdentifier": "disk3s5", "Roles": ["Data"], "CapacityInUse": 90],
        ["Name": "Preboot", "DeviceIdentifier": "disk3s2", "Roles": ["Preboot"], "CapacityInUse": 7],
        ["Name": "VM", "DeviceIdentifier": "disk3s6", "Roles": ["VM"], "CapacityInUse": 3]]]]], format: .xml, options: 0)
    let cs = try APFSInfo.parseContainers(plist)
    let disk = DiskInfoRecord(deviceIdentifier: "disk3s1s1", containerReference: "disk3", isSolidState: true)
    #expect(APFSInfo.otherVolumesBytes(containers: cs, scanned: disk, isRootScan: true) == 10)
    let ext = DiskInfoRecord(deviceIdentifier: "disk3s2", containerReference: "disk3", isSolidState: true)
    #expect(APFSInfo.otherVolumesBytes(containers: cs, scanned: ext, isRootScan: false) == 12 + 90 + 3)
}

@Test func gaugeThresholds() {
    #expect(GaugeLevel.forFraction(0.5) == .green); #expect(GaugeLevel.forFraction(0.85) == .orange); #expect(GaugeLevel.forFraction(0.86) == .red)
}

@Test func liveVolumesIncludeRootFirst() {
    let v = VolumeLister.mountedVolumes()
    #expect(v.first?.mountPath == "/"); #expect(v.first!.totalBytes > 0)
    #expect(APFSInfo.diskInfo(mountPath: "/")?.containerReference != nil)
}
```

- [ ] **Step 2: Run `scripts/test.sh --filter "VolumesTests|HiddenSpaceTests"`.** Expected: FAIL.
- [ ] **Step 3: Implement.** Read volume properties with the URL resource keys `volumeName`, `volumeTotalCapacity`, `volumeAvailableCapacity`, `volumeAvailableCapacityForImportantUsage`, `volumeIsRootFileSystem`, `volumeIsInternal`, `volumeIsRemovable`, `volumeIsLocal`, `volumeLocalizedFormatDescription`. `otherVolumesBytes`: find the container whose `reference == scanned.containerReference`. The base device is the regex `^disk\d+s\d+` match of `scanned.deviceIdentifier`. Exclude the volume equal to the base and, when `isRootScan`, any volume whose roles contain `"System"` or `"Data"`. Sum the rest. `compute`: `hidden = used − scanned` (nil if ≤ 0); `purgeable' = min(purgeable, hidden)`; `other' = min(other, hidden − purgeable')`; `still = hidden − purgeable' − other'`. `diskutil` runs through `Process` with stdout piped. On any failure return nil or [].
- [ ] **Step 4: Run the filter.** Expected: all pass.
- [ ] **Step 5: Commit** `feat(core): volume listing, APFS container info, hidden space`

---

### Task 6: TreeCodec + majes-helper `scan`

**Files:**
- Create: `Sources/MajesCore/TreeCodec.swift`, `Sources/MajesCore/HelperCommand.swift`
- Modify: `Sources/majes-helper/main.swift` → `import MajesCore; import Foundation; exit(HelperCommand.run(arguments: Array(CommandLine.arguments.dropFirst())))`
- Test: `Tests/MajesCoreTests/TreeCodecTests.swift`, `Tests/MajesCoreTests/HelperCommandTests.swift`

**Interfaces:**
- Consumes: `Scanner`, `FileTree` (Tasks 2–4).
- Produces:
```swift
public enum TreeCodecError: Error, Equatable { case badMagic, truncated }
public enum TreeCodec { public static func encode(_ t: FileTree) -> Data; public static func decode(_ d: Data) throws -> FileTree }
public enum HelperCommand {
    /// scan --root P --out F --progress F2 --cancel F3   → 0 ok, 2 usage, 3 cancelled, 4 io error
    public static func run(arguments: [String]) -> Int32
}
public struct HelperProgress: Codable, Equatable { public var files: Int; public var directories: Int; public var bytes: UInt64; public var path: String }
```
Codec format, little-endian: magic `"MJD1"`, `u32 nodeCount`, then for each node in ID order `i32 parent, u16 flags, u64 size, u32 itemCount, u16 nameLen, name UTF-8`, then `u32 virtualCount` and `(i32 id, u8 kind)` pairs. Decode rebuilds `childIDs` from parents and re-sorts. `FileTree` needs an internal init from arrays for this, shared with the builder.

- [ ] **Step 1: Write failing tests:** `roundTripPreservesTree` (sample tree plus a virtual node: same `nodeCount`, sizes, paths, flags, `virtualKind`); `decodeRejectsBadMagic` (`#expect(throws: TreeCodecError.badMagic)`); `decodeRejectsTruncated` (encode, drop the last 3 bytes → `.truncated`); `helperScanWritesDecodableTree` (temp dir with 2 files → `HelperCommand.run(["scan","--root",d,"--out",o,"--progress",p,"--cancel",c]) == 0`, decoded root size equals the `allocated` sum, progress file decodes as `HelperProgress`); `helperScanHonorsCancelFile` (create the cancel file first → returns 3 and writes no out file); `helperRejectsUnknownCommand` (`run(["bogus"]) == 2`).
- [ ] **Step 2: Run `scripts/test.sh --filter "TreeCodecTests|HelperCommandTests"`.** Expected: FAIL.
- [ ] **Step 3: Implement.** The helper scans with `ScanOptions(rootPath:)`, `isCancelled = FileManager.fileExists(cancel)` checked at most every 100 ms, and writes progress JSON atomically (`Data.write(options: .atomic)`). Output files get POSIX permission `0o644` so the non-root app can read them.
- [ ] **Step 4: Run the filter, then `swift build --product majes-helper`.** Expected: pass, and the build succeeds.
- [ ] **Step 5: Smoke-test the binary:** run `$(swift build --show-bin-path)/majes-helper scan --root ~/Downloads --out /tmp/x.mjd --progress /tmp/x.json --cancel /tmp/x.cancel; echo $?`. Expected: `0`.
- [ ] **Step 6: Commit** `feat(core): tree codec and majes-helper scan command`

**Milestone A gate:** `scripts/test.sh` is all green.

---

# Milestone B — Map and browsing UI (Prompt 2)

### Task 7: Sunburst layout, hit test, palette, transition, history, key bindings (MajesMap)

**Files:**
- Create: `Sources/MajesMap/SunburstLayout.swift`, `SunburstHitTest.swift`, `SunburstPalette.swift`, `MapTransition.swift`, `NavigationHistory.swift`, `KeyBindings.swift`. Delete `MajesMap.swift` and `SmokeTests.swift`.
- Test: `Tests/MajesMapTests/SunburstLayoutTests.swift`, `SunburstHitTestTests.swift`, `PaletteTests.swift`, `MapTransitionTests.swift`, `NavigationHistoryTests.swift`, `KeyBindingsTests.swift`

**Interfaces:**
- Consumes: `FileTree`, `NodeID`, `NodeFlags`, `VirtualKind`.
- Produces:
```swift
public struct SunburstConfig: Sendable { public var maxDepth = 6; public var centerRadiusFraction = 0.22; public var minSegmentAngle = 0.0105
    public init(); public func radii(depth: Int, outerRadius: Double) -> (inner: Double, outer: Double) }
public enum SegmentKind: Sendable, Equatable { case directory, file, package, restricted, virtual, smallerObjects }
public struct SunburstSegment: Sendable, Equatable {
    public var node: NodeID            // for .smallerObjects: the parent folder
    public var aggregateStartIndex: Int?   // index into tree.children(node) where the merged tail starts
    public var kind: SegmentKind; public var depth: Int; public var startAngle: Double; public var endAngle: Double
    public var midAngle: Double { get }
}
public enum SunburstLayout { public static func layout(tree: FileTree, center: NodeID, config: SunburstConfig = .init(), expandedPackages: Set<NodeID> = []) -> [SunburstSegment] }
public enum HitResult: Equatable { case center, segment(Int), none }
public enum SunburstHitTest { public static func hit(point: CGPoint, center: CGPoint, outerRadius: Double, segments: [SunburstSegment], config: SunburstConfig) -> HitResult }
public struct RGBA: Equatable, Sendable { public var r, g, b, a: Double }
public enum SunburstPalette { public static func color(for s: SunburstSegment, highlighted: Bool) -> RGBA }
public enum TransitionDirection: Sendable { case zoomIn, zoomOut }
public struct TransitionFrame: Equatable { public var outgoingScale, outgoingAlpha, incomingScale, incomingAlpha: Double }
public enum MapTransition { public static let duration = 0.3; public static func frame(t: Double, direction: TransitionDirection) -> TransitionFrame }
public struct NavigationHistory: Sendable { public init(start: NodeID); public private(set) var current: NodeID
    public var canGoBack: Bool { get }; public var canGoForward: Bool { get }
    public mutating func visit(_ id: NodeID); public mutating func goBack() -> NodeID?; public mutating func goForward() -> NodeID? }
public enum BrowserAction: Equatable, Sendable { case selectPrevious, selectNext, pageUp, pageDown, selectFirst, selectLast, goUp, goBack, goForward, enter, quickLook, toggleCollector, rescanFolder, rescanAll }
public struct KeyModifiers: OptionSet, Sendable { public let rawValue: Int /* command=1 shift=2 option=4 control=8 */ }
public enum KeyBindings { public static func action(keyCode: UInt16, modifiers: KeyModifiers) -> BrowserAction? }
```
Angles are radians, 0 at 12 o'clock, increasing clockwise, in a **y-down** (flipped) view. A point at angle θ and radius r is `(cx + r·sinθ, cy − r·cosθ)`. Hit-test inverse: `θ = atan2(dx, −dy)` normalized to [0, 2π).

- [ ] **Step 1: Write failing tests.** Key assertions:

```swift
// Layout: root 100 = dirs A(50, child file 50), B(30), file C(20)
@Test func anglesProportionalAndNested() {
    let segs = SunburstLayout.layout(tree: t, center: t.root)
    let d1 = segs.filter { $0.depth == 1 }
    #expect(d1.map { $0.endAngle - $0.startAngle }.map { ($0 / (2 * .pi) * 100).rounded() } == [50, 30, 20])
    #expect(segs.contains { $0.depth == 2 && abs($0.endAngle - .pi) < 1e-9 })   // A's child spans A's whole arc
    #expect(d1[2].kind == .file)
}
@Test func tinyChildrenMergeIntoSmallerObjects()   // 1 big + 300 tiny files → depth-1 count == 2, last.kind == .smallerObjects, aggregateStartIndex == 1
@Test func depthIsCapped()                          // 10-deep chain → max depth == 6
@Test func layoutOfEmptyRootIsEmpty()               // root size 0 → []
@Test func singleChildFillsFullCircle()             // one file → start 0, end 2π
@Test func packagesNotExpandedUnlessRequested()     // .app dir with children → no depth-2 segments; with expandedPackages → present
// Hit test: outer 100, center (100,100), segments from anglesProportional
@Test func hitCenterRingAndAngle() {
    #expect(hit((100, 100)) == .center)
    #expect(hit((100 + 30, 100 - 1)) == .segment(indexOfDepth1StartingAt0))   // right side, θ≈π/2 is inside A [0,π)
    #expect(hit((100, 100 + 30)) == .segment(indexOfB))                        // bottom θ=π → B
    #expect(hit((100, -5)) == .none)                                            // outside outer radius
}
@Test func paletteRules()   // files: r==g==b; smallerObjects: a == 0.35; restricted hue ≈ 0.77; highlighted brighter than plain; dirs at θ=0 and θ=π differ in hue
@Test func transitionEndpoints()   // zoomIn t=0 → (1,1,0.6,0); t=1 → (1.5,0,1,1); zoomOut t=1 → (0.6,0,1,1); t clamped to [0,1]
@Test func historyBackForward()     // visit 1,2 → back == 1, back == 0, forward == 1; visit 5 clears forward
@Test func keyTable() {
    #expect(KeyBindings.action(keyCode: 126, modifiers: []) == .selectPrevious)
    #expect(KeyBindings.action(keyCode: 126, modifiers: .command) == .goUp)
    #expect(KeyBindings.action(keyCode: 33, modifiers: .command) == .goBack)
    #expect(KeyBindings.action(keyCode: 30, modifiers: .command) == .goForward)
    #expect(KeyBindings.action(keyCode: 49, modifiers: []) == .quickLook)
    #expect(KeyBindings.action(keyCode: 51, modifiers: .command) == .toggleCollector)
    #expect(KeyBindings.action(keyCode: 15, modifiers: [.command, .shift]) == .rescanAll)
}
```
Key codes: ↑126 ↓125 PgUp116 PgDn121 Home115 End119 Return36 Enter76 Space49 Delete51 `[`33 `]`30 R15.

- [ ] **Step 2: Run `scripts/test.sh --filter MajesMapTests`.** Expected: FAIL.
- [ ] **Step 3: Implement.** Layout recursion `place(node, depth, a0, a1)` over `tree.children(node)` (sizes > 0 only): child span = `(a1−a0)·size/parentSize`. At the first child whose span < `minSegmentAngle`, emit one `.smallerObjects` segment covering the remaining arc, then stop. Recurse into `.directory`/`.virtual` (and expanded packages) while `depth < maxDepth`. Kind priority: virtual > restricted > package > directory > file. Radii: `r0 = outer·0.22`, ring width `(outer − r0)/maxDepth`. Palette in HSB, converted to RGB:

| kind | hue | sat | bri | alpha |
|---|---|---|---|---|
| directory / package | midAngle/2π | 0.62 | max(0.45, 0.92 − 0.07·(depth−1)) | 1 |
| file | — | 0 | max(0.40, 0.72 − 0.04·(depth−1)) | 1 |
| restricted | 0.77 | 0.45 | 0.75 | 1 |
| virtual | — | 0 | 0.45 | 0.6 |
| smallerObjects | as directory at the parent's hue | 0.62 | as directory | 0.35 |
| highlighted | same | sat − 0.1 | bri + 0.1 (cap 1) | same |

Transition uses smoothstep easing `e = t²(3−2t)`, linear-interpolated between the endpoints in the test.
- [ ] **Step 4: Run the filter.** Expected: all pass.
- [ ] **Step 5: Commit** `feat(map): sunburst layout, hit test, palette, transitions, history, key bindings`

---

### Task 8: App shell, bundle assembly, Disks overview

**Files:**
- Create: `Resources/Info.plist`, `scripts/build-app.sh`, `scripts/run.sh`, `Sources/MajesCore/StarredFolders.swift`, `Sources/MajesDisk/MajesDiskApp.swift`, `Sources/MajesDisk/AppDelegate.swift`, `Sources/MajesDisk/AppModel.swift`, `Sources/MajesDisk/Views/OverviewView.swift`, `Sources/MajesDisk/Views/VolumeRowView.swift`, `Sources/MajesDisk/Views/GaugeView.swift`
- Delete: `Sources/MajesDisk/main.swift`
- Test: `Tests/MajesCoreTests/StarredFoldersTests.swift`

**Interfaces:**
- Consumes: `VolumeLister`, `VolumeInfo`, `GaugeLevel`, `ByteFormat`.
- Produces:
```swift
public struct StarredFolders { public init(defaults: UserDefaults = .standard); public var paths: [String] { get }
    public func add(_ p: String); public func remove(_ p: String); public func contains(_ p: String) -> Bool }  // key "starredFolders"
@MainActor @Observable final class AppModel {
    enum Screen { case overview, scanning(ScanSession), results(ResultsModel) }
    var screen: Screen; var volumes: [VolumeInfo]; var starred: [String]; var optionKeyDown: Bool
    func refreshVolumes(); func startScan(path: String, asAdministrator: Bool); func chooseFolderAndScan()
    func showOverview()
}
```
`ScanSession` and `ResultsModel` are stubbed here (empty `@Observable` classes) and filled in Tasks 9–10.

- [ ] **Step 1: Write the failing test** `starredFoldersPersist`: use `UserDefaults(suiteName: "test-\(UUID())")!`; add "/a", add "/a" again (no duplicate), add "/b"; a new `StarredFolders` on the same defaults sees `["/a","/b"]`; remove "/a" leaves `["/b"]`.
- [ ] **Step 2: Run** `scripts/test.sh --filter StarredFoldersTests`. Expected: FAIL. **Step 3:** implement. **Step 4:** run. Expected: PASS.
- [ ] **Step 5: Write `Resources/Info.plist`** with these keys: `CFBundleName`/`CFBundleDisplayName` MajesDisk, `CFBundleIdentifier` com.majesdisk.MajesDisk, `CFBundleExecutable` MajesDisk, `CFBundlePackageType` APPL, `CFBundleShortVersionString` 0.1.0, `CFBundleVersion` 1, `CFBundleIconFile` AppIcon, `LSMinimumSystemVersion` 14.0, `NSHighResolutionCapable` true, `NSPrincipalClass` NSApplication, `LSApplicationCategoryType` public.app-category.utilities. Include `CFBundleDocumentTypes` with one entry: `CFBundleTypeRole` Viewer, `LSItemContentTypes` [public.folder, public.volume], so a disk or folder dropped on the Dock icon opens. Usage strings:
  - `NSDesktopFolderUsageDescription` / `NSDocumentsFolderUsageDescription` / `NSDownloadsFolderUsageDescription`: "MajesDisk measures the files in this folder to show what uses your disk space."
  - `NSRemovableVolumesUsageDescription` / `NSNetworkVolumesUsageDescription`: "MajesDisk measures the files on this volume to show what uses its space."
- [ ] **Step 6: Write `scripts/build-app.sh [debug|release]`** (default release). It runs `swift build -c $CFG --product MajesDisk` and `--product majes-helper`, takes `BIN=$(swift build -c $CFG --show-bin-path)`, and recreates `dist/MajesDisk.app/Contents/{MacOS,Helpers,Resources}`. It copies the binaries, `Info.plist`, and `Resources/AppIcon.icns` if present. It signs the helper first and then the app, each with `codesign --force --options runtime --timestamp=none -s "${MAJESDISK_SIGN_IDENTITY:--}"`, then runs `codesign --verify --strict dist/MajesDisk.app` and echoes the app path. `scripts/run.sh`: `scripts/build-app.sh debug && open dist/MajesDisk.app --args "$@"` (launching through `open` makes TCC attribute access to MajesDisk, not Terminal).
- [ ] **Step 7: Implement the app shell.**
  - `MajesDiskApp` (`@main`) has a `WindowGroup` (min 900×600) showing `RootView`, which switches on `model.screen`, plus a `Settings` scene (placeholder `Text`, filled in Task 15). It uses `@NSApplicationDelegateAdaptor(AppDelegate.self)`. `AppDelegate.application(_:open:)` forwards the first URL to `model.startScan(path:asAdministrator:false)`.
  - `OverviewView` layout, top to bottom: a header "Disks"; a `VolumeRowView` per volume (`NSWorkspace.shared.icon(forFile:)`, name, `GaugeView` with the fraction from `usedFraction(purgeableAsUsed: model.optionKeyDown)` and its `GaugeLevel` color, the text "\(ByteFormat) free" with a `.help` tooltip showing used, and a "Scan" button with a `Menu` offering "Scan" and "Scan as Administrator"); then a "Folders" section with starred rows (star toggle, path, Scan) and a "Scan Folder…" button (`NSOpenPanel`, directories only).
  - The whole view takes `.onDrop(of: [.fileURL])` to start a scan.
  - Volumes refresh on a 2 s `Timer`. An `NSEvent.addLocalMonitorForEvents(.flagsChanged)` sets `optionKeyDown`.
- [ ] **Step 8: Verify:** run `scripts/build-app.sh debug`, expected `codesign` verify OK, then `open dist/MajesDisk.app`. Expected: the window lists "Macintosh HD" first with a colored gauge and free space, and holding ⌥ grows the gauge fill when purgeable > 0.
- [ ] **Step 9: Commit** `feat(app): app bundle, disks overview, starred folders`

---

### Task 9: Scan session and progress screen

**Files:**
- Create: `Sources/MajesDisk/ScanSession.swift`, `Sources/MajesDisk/Views/ScanProgressView.swift`
- Modify: `Sources/MajesDisk/AppModel.swift`, `Sources/MajesDisk/MajesDiskApp.swift` (launch arg `--scan <path>` calls `startScan` on appear)

**Interfaces:**
- Consumes: `Scanner`, `ScanOptions.recommendedConcurrency`, `APFSInfo`, `HiddenSpace`, `VolumeInfo`.
- Produces:
```swift
@MainActor @Observable final class ScanSession {
    let rootPath: String; let asAdministrator: Bool
    var progress: ScanProgress; var state: State   // enum State { case running, finished(FileTree), failed(String), cancelled }
    init(rootPath: String, asAdministrator: Bool, volume: VolumeInfo?)
    func start(); func cancel()
}
```

- [ ] **Step 1: Implement `ScanSession.start()`.** Run a `Task.detached(priority: .userInitiated)` that does the following:
  1. Compute `concurrency = ScanOptions.recommendedConcurrency(isSolidState: APFSInfo.diskInfo(mountPath:)?.isSolidState)`.
  2. Run `Scanner.run`. Progress is delivered to the main actor at most every 100 ms. `isCancelled` reads a lock-protected flag.
  3. If `volume?.mountPath == rootPath`, compute `HiddenSpace.compute(usedBytes: volume.usedBytes, scannedBytes: tree.size(root), purgeableBytes: volume.purgeableBytes, otherVolumesBytes: APFSInfo.otherVolumesBytes(containers: APFSInfo.containers(), scanned: disk, isRootScan: rootPath == "/"))` and attach it.
  4. Finish in `.finished(tree)`.

  The `asAdministrator` branch is a `fatalError("Task 16")` placeholder that Task 16 replaces.
- [ ] **Step 2: `AppModel.startScan`** creates the session and sets `screen = .scanning`. When it finishes, it sets `screen = .results(ResultsModel(tree:volume:))`. On cancel it returns to the overview.
- [ ] **Step 3: `ScanProgressView`:** a large rotating flower (12 petals drawn with SwiftUI `Canvas`, rotating via `TimelineView(.animation)`), the root name, "N files · ByteFormat(bytes)", the current path in a truncated-middle monospaced caption, and a "Stop" button.
- [ ] **Step 4: Verify:** `scripts/run.sh --scan ~/Downloads`. Expected: progress appears, then the (stub) results screen. Then `scripts/run.sh --scan /`. Expected: counts climb at about 10 Hz and Stop returns to the overview within 0.5 s.
- [ ] **Step 5: Commit** `feat(app): scan session with progress and cancel`

---

### Task 10: Sunburst view and results navigation model

**Files:**
- Create: `Sources/MajesDisk/ResultsModel.swift`, `Sources/MajesDisk/Map/SunburstNSView.swift`, `Sources/MajesDisk/Map/SunburstView.swift`, `Sources/MajesDisk/Map/RGBA+NSColor.swift`

**Interfaces:**
- Consumes: `SunburstLayout`, `SunburstHitTest`, `SunburstPalette`, `MapTransition`, `NavigationHistory`, `FileTree`.
- Produces:
```swift
@MainActor @Observable final class ResultsModel {
    let tree: FileTree; let volume: VolumeInfo?
    var history: NavigationHistory; var center: NodeID { history.current }
    var hovered: NodeID?; var hoveredSmallerObjects: (parent: NodeID, start: Int)?
    var selected: NodeID?; var expandedPackages: Set<NodeID>; var treeVersion: Int
    var sidebarFolder: NodeID { get }   // hovered folder if hovering a folder, else center
    init(tree: FileTree, volume: VolumeInfo?)
    func enter(_ id: NodeID); func goUp(); func goBack(); func goForward(); func perform(_ a: BrowserAction)
}
final class SunburstNSView: NSView   // isFlipped = true; owned by SunburstView (NSViewRepresentable) bound to ResultsModel
```

- [ ] **Step 1: Implement `ResultsModel` navigation.** `enter` accepts only directories, virtual nodes and expanded packages. `goUp` goes to the parent unless at root. Each change calls `history.visit` and records the transition direction (`zoomIn` for enter, `zoomOut` for up). `perform` maps `BrowserAction` to these operations; selection actions move `selected` through `tree.children(sidebarFolder)` (page = 10 rows).
- [ ] **Step 2: Implement `SunburstNSView`.**
  - Cache `segments` and recompute when `center`, `treeVersion` or `expandedPackages` change.
  - `draw(_:)`: `outerRadius = min(bounds)/2 − 12`. Draw each segment as an annular wedge path (`CGMutablePath` `addArc` outer clockwise, inner back), filled with the palette color and stroked 0.5 pt in the window background color. The hovered segment is drawn highlighted.
  - Center disk: the hovered (else center) node's name (13 pt semibold, max 2 lines) and `ByteFormat` size (17 pt).
  - `NSTrackingArea` (`.mouseMoved`, `.activeInKeyWindow`, `.inVisibleRect`): `mouseMoved` runs the hit test and sets `model.hovered` or `hoveredSmallerObjects`.
  - `mouseUp`: center → `goUp`; segment → `enter` (smaller objects → set `hoveredSmallerObjects` and let the sidebar expand); ⌘-click → `NSWorkspace.shared.activateFileViewerSelecting`.
  - On a center change, run the 0.3 s transition with a 60 Hz `Timer`, drawing the old segments with `outgoingScale/Alpha` and the new ones with `incoming…` (scale about the center via CTM).
  - `magnify(with:)`: accumulate; > 0.3 → `enter(hovered)`, < −0.3 → `goUp()`.
  - `acceptsFirstResponder = true`. `keyDown` → `KeyBindings.action` → `model.perform`, else `super`.
- [ ] **Step 3: Temporarily show `SunburstView` full-window for `.results`.** Verify with `scripts/run.sh --scan ~/Library`: rings render with rainbow folders and grey files; hover highlights a segment and updates the center label; click zooms in with animation; clicking the center zooms out; ⌘[ and ⌘] navigate history; pinch works on the trackpad.
- [ ] **Step 4: Commit** `feat(app): interactive sunburst map with animated navigation`

---

### Task 11: Results screen: sidebar, toolbar, breadcrumbs, menus

**Files:**
- Create: `Sources/MajesDisk/Views/ResultsView.swift`, `Sources/MajesDisk/Views/SidebarView.swift`, `Sources/MajesDisk/Views/BreadcrumbView.swift`, `Sources/MajesDisk/Views/ItemInfoView.swift`, `Sources/MajesDisk/Commands.swift`
- Modify: `Sources/MajesDisk/MajesDiskApp.swift` (add `.commands { MajesCommands() }`)

**Interfaces:**
- Consumes: `ResultsModel` (Task 10), `SunburstPalette`.
- Produces: `struct ResultsView: View`. `MajesCommands` exposes menu items via `@FocusedValue(\.resultsModel)`.

- [ ] **Step 1: Build `ResultsView`.**
  - Toolbar: ◀ ▶ (disabled per `canGoBack`/`canGoForward`), ⬆ (⌘↑), `BreadcrumbView` (root…center path components, each clickable → `history.visit`), and a trailing "Rescan" (wired in Task 18) and "Disks" button → `appModel.showOverview()`.
  - Body: `HSplitView { SidebarView (min 260, ideal 300); SunburstView }`. The bottom area is reserved for the Collector bar (Task 14).
- [ ] **Step 2: Build `SidebarView`.**
  - Header: `sidebarFolder` name, size, and "N items".
  - `List(selection: $model.selected)` of `tree.children(sidebarFolder)`. When `hoveredSmallerObjects` is set, show the full children list from `start` with a section header "Smaller objects".
  - Each row: a 10 pt circle in the segment's palette color (grey for files, purple for restricted), the name (strikethrough when `.deleted`; `secondaryLink` rows show "hard link" in secondary text), a right-aligned size, and a thin proportional bar.
  - Hovering a row sets `model.hovered`. Double-click → `enter`.
  - Bottom: `ItemInfoView` for the hovered/selected node: full path (selectable), kind (Folder/File/Package/Restricted/Virtual), size, items, and modification date (lazy `FileManager.attributesOfItem`, `nil` for virtual nodes).
- [ ] **Step 3: Add `MajesCommands`.**
  - "Go" menu: Enclosing Folder ⌘↑, Back ⌘[, Forward ⌘], Open Pointed Folder ↩.
  - "File" menu: Scan Folder… ⌘O, Rescan Folder ⌘R, Rescan Disk ⇧⌘R, Forget Scan Results (Tasks 18 wires the rescans).
- [ ] **Step 4: Verify** with `scripts/run.sh --scan /`:
  - The sidebar follows the hovered folder, and hovering a row highlights its segment.
  - Breadcrumb clicks navigate. ↑/↓/Home/End move the selection.
  - For a whole-disk scan, "Hidden space" appears as a dark grey segment. Clicking it shows Purgeable / Other volumes / Still hidden.
- [ ] **Step 5: Commit** `feat(app): results sidebar, breadcrumbs, info panel, menu commands`

---

### Task 12: Quick Look, context menu, Reveal in Finder

**Files:**
- Create: `Sources/MajesDisk/QuickLook/QuickLookController.swift`, `Sources/MajesDisk/Views/NodeContextMenu.swift`
- Modify: `Sources/MajesDisk/Map/SunburstNSView.swift`, `Sources/MajesDisk/Views/SidebarView.swift`

**Interfaces:**
- Consumes: `ResultsModel`, `FileTree.path`.
- Produces: `@MainActor final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate { static let shared; func toggle(path: String) }` and `struct NodeContextMenu: View { let id: NodeID; let model: ResultsModel }`.

- [ ] **Step 1: Implement Quick Look.**
  - `QuickLookController.toggle` sets the item URL. If the panel is visible, it calls `orderOut`; otherwise `makeKeyAndOrderFront`.
  - `SunburstNSView` overrides `acceptsPreviewPanelControl` (true), `beginPreviewPanelControl` (set `dataSource`/`delegate` to the shared controller), and `endPreviewPanelControl`.
  - `BrowserAction.quickLook` (Space) previews `hovered ?? selected`. Virtual and smaller-objects items are ignored.
- [ ] **Step 2: Build the context menu.**
  - Shared items: Preview (Space), Reveal in Finder, Copy Path (`NSPasteboard`), Move to Collector (⌘⌫, wired in Task 14), Show Package Contents / Hide Package Contents (packages only; toggles `expandedPackages` and bumps `treeVersion`), and Rescan This Folder (Task 18).
  - The SwiftUI version is `.contextMenu` on sidebar rows. `SunburstNSView` builds the same items as an `NSMenu` in `menu(for:)`.
- [ ] **Step 3: Verify:** Space on a hovered image shows the Quick Look panel, and pressing Space again closes it. Right-click → Reveal in Finder selects the file. "Show Package Contents" on an `.app` renders its rings.
- [ ] **Step 4: Commit** `feat(app): Quick Look, context menus, reveal in Finder`

**Milestone B gate:** `scripts/test.sh` is green, and the manual checks in Tasks 8–12 pass on a `/` scan.

---

# Milestone C — Cleanup and privileges (Prompt 3)

### Task 13: Protected paths, Collector model, Deleter

**Files:**
- Create: `Sources/MajesCore/ProtectedPaths.swift`, `Sources/MajesCore/Collector.swift`, `Sources/MajesCore/Deleter.swift`
- Test: `Tests/MajesCoreTests/ProtectedPathsTests.swift`, `CollectorTests.swift`, `DeleterTests.swift`

**Interfaces:**
- Consumes: `FileTree`, `VirtualKind`.
- Produces:
```swift
public enum ProtectionVerdict: Equatable, Sendable { case allowed, protected(String) }
public enum ProtectedPaths { public static func verdict(for path: String, homeDirectory: String = NSHomeDirectory(), volumeRoots: [String] = []) -> ProtectionVerdict }
public enum CollectorAddResult: Equatable { case added, alreadyCovered, rejected(String) }
public struct Collector: Sendable {
    public private(set) var items: [NodeID]
    public init()
    public mutating func add(_ id: NodeID, in tree: FileTree, verdict: (String) -> ProtectionVerdict) -> CollectorAddResult
    public mutating func remove(_ id: NodeID); public mutating func removeAll()
    public func contains(_ id: NodeID) -> Bool; public func totalSize(in tree: FileTree) -> UInt64
}
public enum DeleteMode: String, Sendable { case permanent, moveToTrash }
public enum DeleteFailure: Error, Equatable, Sendable { case protected(String), notFound, permissionDenied, other(String) }
public struct DeleteOutcome: Sendable, Equatable { public var path: String; public var failure: DeleteFailure? }
public enum Deleter { public static func delete(paths: [String], mode: DeleteMode, verdict: (String) -> ProtectionVerdict) -> [DeleteOutcome] }
```

- [ ] **Step 1: Write failing tests:**

```swift
@Test func protectedPathRules() {
    let h = "/Users/me"
    for p in ["/", "/System", "/System/Library/Fonts", "/Library", "/Applications", "/Users", h, "\(h)/Library",
              "\(h)/Desktop", "\(h)/Documents", "\(h)/Downloads", "/usr/bin", "/private/var", "/private/var/db/x", "/Volumes", "/Volumes/Ext", "/dev"] {
        #expect(ProtectedPaths.verdict(for: p, homeDirectory: h, volumeRoots: ["/Volumes/Ext"]) != .allowed, "\(p)")
    }
    for p in ["/Applications/Foo.app", "\(h)/Library/Caches", "\(h)/Downloads/big.dmg", "/usr/local/lib", "/Volumes/Ext/movie.mov", "/Library/Caches/x"] {
        #expect(ProtectedPaths.verdict(for: p, homeDirectory: h, volumeRoots: ["/Volumes/Ext"]) == .allowed, "\(p)")
    }
    #expect(ProtectedPaths.verdict(for: "\(h)/", homeDirectory: h) != .allowed)   // trailing slash normalized
}
@Test func collectorCoversDescendantsAndRejects()
    // add /r/a → .added; add /r/a/g → .alreadyCovered; add /r → .rejected (root);
    // add child then its parent → parent replaces child (items == [parent]); totalSize sums;
    // virtual .hiddenSpace/.otherVolumes/.stillHidden → .rejected; .purgeable → .added
@Test func deleterRemovesFilesAndFolders()        // permanent: file and non-empty dir gone; outcomes have nil failure
@Test func deleterRemovesSymlinkNotTarget()       // symlink → dir: link gone, target dir and its file still exist
@Test func deleterRefusesProtectedPath()          // verdict closure returns .protected("x") → failure == .protected("x"), file still exists
@Test func deleterReportsMissing()                // nonexistent → .notFound
@Test func deleterPermissionDenied()              // file inside chmod 555 dir (skip if root) → .permissionDenied
@Test func deleterMovesToTrash()                  // .moveToTrash → original gone (trashed URL exists; clean it up)
```

- [ ] **Step 2: Run `scripts/test.sh --filter "ProtectedPathsTests|CollectorTests|DeleterTests"`.** Expected: FAIL.
- [ ] **Step 3: Implement.** Normalize with `(path as NSString).standardizingPath` and strip a trailing "/" (except root).
  - **Exact-protected:** `/ /System /Library /Applications /Users /usr /bin /sbin /private /private/var /private/etc /private/tmp /var /etc /tmp /opt /cores /dev /Volumes`, `home`, `home/Library`, `home/Desktop`, `home/Documents`, `home/Downloads`, `home/Pictures`, `home/Music`, `home/Movies`, plus `volumeRoots` → `.protected("This folder is essential to macOS or your account.")`.
  - **Prefix-protected:** `/System/ /bin/ /sbin/ /private/var/db/ /dev/` and `/usr/` except `/usr/local/` → `.protected("This item is protected by macOS.")`.
  - **Ancestor of home:** any path that is an ancestor of `home` → protected.
  - **Collector:** root → `.rejected("The scanned folder itself can't be collected.")`. Virtual kinds other than purgeable → `.rejected("This is a summary of space, not a file.")`. Then the protected check. `Deleter` maps `CocoaError.fileNoSuchFile`/`ENOENT` → `.notFound` and `fileWriteNoPermission` (513)/`EACCES`/`EPERM` → `.permissionDenied`.
- [ ] **Step 4: Run the filter.** Expected: all pass.
- [ ] **Step 5: Commit** `feat(core): protected paths, collector, deleter`

---

### Task 14: Collector UI and deletion flow

**Files:**
- Create: `Sources/MajesDisk/Views/CollectorBarView.swift`, `Sources/MajesDisk/DeletionController.swift`
- Modify: `ResultsModel.swift` (add `var collector: Collector`, `func toggleCollector(_ id: NodeID) -> String?` returning a rejection message), `ResultsView.swift`, `SunburstNSView.swift` (drag source), `SidebarView.swift` (`.onDrag`), `NodeContextMenu.swift`

**Interfaces:**
- Consumes: `Collector`, `Deleter`, `ProtectedPaths`, `DeleteMode`, `FileTree.markDeleted`.
- Produces:
```swift
@MainActor @Observable final class DeletionController {
    enum Phase { case idle, countdown(remaining: Int), deleting, finished([DeleteOutcome]) }
    var phase: Phase
    func begin(model: ResultsModel)   // 5 s countdown → delete
    func cancel()
}
```
`UserDefaults` key `"deleteMode"` (`DeleteMode.rawValue`, default `"permanent"`).

- [ ] **Step 1: Implement drag sources.**
  - `SunburstNSView.mouseDragged` (after a 4 pt threshold, on a real node segment) starts `beginDraggingSession` with an `NSPasteboardItem` holding `.fileURL` for the node path. The drag image is the segment wedge rendered to an `NSImage`.
  - Sidebar rows use `.onDrag { NSItemProvider(object: URL(fileURLWithPath: path) as NSURL) }`.
- [ ] **Step 2: Build `CollectorBarView`** (height 56, at the bottom of `ResultsView`).
  - `.onDrop(of: [.fileURL])` resolves each URL → `tree.node(atPath:)` → `model.toggleCollector`. A rejection shows an alert with the message.
  - Collapsed: a tray icon, "Drag files here to delete" when empty, else "N items · ByteFormat(total)" and a red "Delete" button.
  - Clicking the bar toggles a popover list: rows with color dot, name, size, and an ✕ button that removes the item. Rows support Space for Quick Look and drag back out to remove.
  - During countdown the button turns into "Cancel (N)". The map shows collected nodes at 0.35 alpha.
- [ ] **Step 3: `DeletionController.begin`.**
  - Count down 5→1 at 1 s steps, then `deleting`.
  - Purgeable virtual items are routed to Task 17's `PurgeAction` (placeholder no-op here).
  - Paths run through `Deleter.delete(paths:mode:verdict:)` off the main thread.
  - For each successful outcome: `tree.markDeleted(id)`, remove it from the collector, and `treeVersion += 1`.
  - Failures show an alert listing path and reason. If any failure is `.permissionDenied`, the alert adds a "Delete as Administrator" button, wired in Task 16.
  - Afterwards, call `appModel.refreshVolumes()`.
- [ ] **Step 4: Wire ⌘⌫ (`BrowserAction.toggleCollector`) and the context menu "Move to Collector".**
- [ ] **Step 5: Verify** on a scratch folder with `mkdir -p /tmp/majestest/a && mkfile 50m /tmp/majestest/a/x && mkfile 20m /tmp/majestest/y`, then `scripts/run.sh --scan /tmp/majestest`:
  - Dragging `a` into the Collector shows "1 item · 52.4 MB" (52,4 MB in a comma-decimal locale).
  - Delete then Cancel at 3 → nothing is deleted.
  - Delete and wait 5 s → `a` vanishes from the map and the root size drops. `ls /tmp/majestest` shows only `y`.
  - Dragging `/tmp/majestest` itself is rejected with a message.
- [ ] **Step 6: Commit** `feat(app): collector bar, drag to collect, countdown deletion`

---

### Task 15: Full Disk Access detection and Settings

**Files:**
- Create: `Sources/MajesCore/FullDiskAccess.swift`, `Sources/MajesDisk/Views/SettingsView.swift`, `Sources/MajesDisk/Views/FullDiskAccessBanner.swift`
- Modify: `MajesDiskApp.swift` (Settings scene → `SettingsView`), `OverviewView.swift` (banner)
- Test: `Tests/MajesCoreTests/FullDiskAccessTests.swift`

**Interfaces:**
- Produces:
```swift
public enum FullDiskAccess {
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    public static var defaultProbePaths: [String] { get }   // ~/Library/Application Support/com.apple.TCC/TCC.db, /Library/Application Support/com.apple.TCC/TCC.db, ~/Library/Safari/Bookmarks.plist
    /// true = readable, false = EPERM/EACCES on the first existing probe, nil = no probe exists
    public static func isGranted(probePaths: [String] = defaultProbePaths) -> Bool?
}
```

- [ ] **Step 1: Write failing tests:** a readable temp file → `true`; a `chmod 000` temp file (skip as root) → `false`; only missing paths → `nil`; `[missing, readable]` → `true` (missing paths are skipped).
- [ ] **Step 2: Run** `scripts/test.sh --filter FullDiskAccessTests`. Expected: FAIL. **Step 3:** implement with `open(O_RDONLY)` + `close`. **Step 4:** run. Expected: PASS.
- [ ] **Step 5: Build the UI.**
  - **`FullDiskAccessBanner`** (on the overview when `isGranted != true`): "MajesDisk can't see everything. Grant Full Disk Access so protected folders (Mail, Messages, Safari, app containers) are measured instead of counted as hidden space." Buttons: "Open System Settings" (`NSWorkspace.open(settingsURL)`) and "Reveal MajesDisk" (`activateFileViewerSelecting([Bundle.main.bundleURL])`, so the user can drag the app into the list).
  - **Re-check:** every time the app becomes active (`NSApplication.didBecomeActiveNotification`). Once it flips to granted, show "Relaunch MajesDisk to apply" with a button that relaunches: `open -n` the bundle via `Process`, then `NSApp.terminate`.
  - **`SettingsView` tabs:** General (Picker "When deleting: Delete immediately (frees space now) / Move to Trash" bound to `@AppStorage("deleteMode")`); Full Disk Access (status ✅/⚠️, the same buttons, numbered instructions "1. Open System Settings › Privacy & Security › Full Disk Access 2. Turn on MajesDisk (or click + and choose it) 3. Relaunch MajesDisk", and a note that ad-hoc-signed development builds need re-granting after each rebuild); Administrator (an explanation of what Scan as Administrator does, and that it asks for your password each time).
- [ ] **Step 6: Verify:** build, run, and confirm the banner shows. The button opens the FDA pane. Grant access, return, see the relaunch prompt, relaunch, and confirm the banner is gone. Rescan `/` and confirm hidden space shrank.
- [ ] **Step 7: Commit** `feat(app): Full Disk Access detection, banner, settings`

---

### Task 16: Admin runner, Scan as Administrator, Delete as Administrator

**Files:**
- Create: `Sources/MajesCore/AdminRunner.swift`
- Modify: `Sources/MajesCore/HelperCommand.swift` (add `delete`), `Sources/MajesDisk/ScanSession.swift` (admin branch), `Sources/MajesDisk/DeletionController.swift` (admin retry)
- Test: `Tests/MajesCoreTests/AdminRunnerTests.swift`, extend `HelperCommandTests.swift`

**Interfaces:**
- Consumes: `HelperCommand`, `TreeCodec`, `ProtectedPaths`, `HelperProgress`.
- Produces:
```swift
public enum AdminRunnerError: Error, Equatable { case cancelled, failed(status: Int32, message: String) }
public struct AdminRunner: Sendable {
    public var administrator: Bool; public var prompt: String
    public init(administrator: Bool = true, prompt: String = "MajesDisk needs administrator access.")
    public static func osascriptArguments(command: [String], administrator: Bool, prompt: String) -> [String]
    public func run(_ command: [String]) async throws -> String     // stdout of the command
}
// HelperCommand: delete --home H <path>...  → prints one JSON line per path: {"path":…, "error": null | "protected" | "notFound" | "permissionDenied" | "<msg>"}; exit 0
```

- [ ] **Step 1: Write failing tests:**

```swift
@Test func passesArgumentsWithoutShellInjection() async throws {
    let evil = #"it's "q" $HOME; touch /tmp/pwned-\#(UUID())"#
    let out = try await AdminRunner(administrator: false).run(["/bin/echo", evil])
    #expect(out == evil)
}
@Test func reportsFailureStatus() async {
    await #expect(throws: AdminRunnerError.self) { try await AdminRunner(administrator: false).run(["/usr/bin/false"]) }
}
@Test func helperDeleteRefusesProtected()   // run(["delete","--home","/Users/me","/Users/me","<tmpfile>"]) → tmpfile removed, JSON line for /Users/me has error "protected"
```

- [ ] **Step 2: Run** `scripts/test.sh --filter "AdminRunnerTests|HelperCommandTests"`. Expected: FAIL.
- [ ] **Step 3: Implement `osascriptArguments`** exactly as below. `argv` items are quoted by AppleScript, never interpolated:

```swift
["-e", "on run argv",
 "-e", "set cmd to \"\"",
 "-e", "repeat with a in argv",
 "-e", "set cmd to cmd & quoted form of (a as text) & \" \"",
 "-e", "end repeat",
 "-e", administrator ? "return do shell script cmd with prompt \(appleScriptLiteral(prompt)) with administrator privileges"
                     : "return do shell script cmd",
 "-e", "end run"] + command
```
`run` launches `/usr/bin/osascript` via `Process`, reading stdout and stderr on a background thread and resuming the continuation on termination. Exit 0 → trimmed stdout. Stderr containing `(-128)` → `.cancelled`. Anything else → `.failed`.
- [ ] **Step 4: Run the filter.** Expected: PASS.
- [ ] **Step 5: Admin scan in `ScanSession`.**
  - Create the temp dir `FileManager.default.temporaryDirectory/MajesDisk-<UUID>/`.
  - `helper = Bundle.main.bundleURL.appending(path: "Contents/Helpers/majes-helper").path`.
  - Start `AdminRunner().run([helper, "scan", "--root", root, "--out", out, "--progress", prog, "--cancel", cancel])`. Meanwhile poll `prog` every 250 ms and decode `HelperProgress` into `progress`.
  - `cancel()` creates the cancel file.
  - On success, `TreeCodec.decode` the output, attach hidden space as in Task 9, then delete the temp dir. `.cancelled` (the user dismissed the password prompt) returns to the overview silently.
- [ ] **Step 6: Admin delete.** "Delete as Administrator" runs `AdminRunner().run([helper, "delete", "--home", NSHomeDirectory()] + deniedPaths)`, parses the JSON lines, and applies `markDeleted` for successes.
- [ ] **Step 7: Verify.**
  - Overview → Macintosh HD → Scan as Administrator shows the macOS password dialog with the MajesDisk prompt, then progress.
  - The results show `/private/var/db` and other users' homes with sizes, and hidden space is smaller than in a normal scan.
  - Then check TCC under root. If `~/Library/Mail` still reads as 0 under an admin scan, add `majes-helper` to the FDA list too, and record that instruction in the Settings Administrator tab.
  - Create a root-owned scratch file with `sudo mkfile 5m /tmp/rootfile` (the user runs this), scan `/tmp`, collect it, Delete: the denial offers "Delete as Administrator", which succeeds.
- [ ] **Step 8: Commit** `feat: scan and delete as administrator via majes-helper`

---

### Task 17: Local snapshots sheet and purgeable purge

**Files:**
- Create: `Sources/MajesCore/Snapshots.swift`, `Sources/MajesDisk/Views/SnapshotsSheet.swift`, `Sources/MajesDisk/PurgeAction.swift`
- Modify: `Commands.swift` (menu "Disk › Local Snapshots…"), `VolumeRowView.swift` (the Scan menu gains "Local Snapshots…"), `DeletionController.swift` (route purgeable)
- Test: `Tests/MajesCoreTests/SnapshotsTests.swift`

**Interfaces:**
- Consumes: `AdminRunner`.
- Produces:
```swift
public struct LocalSnapshot: Equatable, Sendable, Identifiable { public var id: String { name }; public var name: String; public var timeMachineDate: String?   // "YYYY-MM-DD-HHMMSS" for com.apple.TimeMachine.*.local
    public var isDeletable: Bool { timeMachineDate != nil } }
public enum Snapshots {
    public static func parse(_ tmutilOutput: String) -> [LocalSnapshot]
    public static func list(mountPath: String) -> [LocalSnapshot]                       // /usr/bin/tmutil listlocalsnapshots <mount>
    public static func deleteCommand(_ s: LocalSnapshot) -> [String]?                    // ["/usr/bin/tmutil","deletelocalsnapshots", date]
    public static func purgeCommand(mountPath: String) -> [String]                       // ["/usr/bin/tmutil","thinlocalsnapshots", mount, "999999999999999", "4"]
}
```

- [ ] **Step 1: Write failing tests:** parse `"Snapshots for disk /:\ncom.apple.TimeMachine.2026-10-13-101010.local\ncom.bombich.ccc.123\n"` → 2 snapshots, the first with `timeMachineDate == "2026-10-13-101010"` and `isDeletable`, the second not deletable. An empty listing gives `[]`. `deleteCommand` for the CCC snapshot is nil. `purgeCommand(mountPath: "/")` equals the exact array above.
- [ ] **Step 2: Run** `scripts/test.sh --filter SnapshotsTests`. Expected: FAIL. **Step 3:** implement (regex `^com\.apple\.TimeMachine\.(\d{4}-\d{2}-\d{2}-\d{6})\.local$`). **Step 4:** run. Expected: PASS.
- [ ] **Step 5: Build the UI.**
  - **`SnapshotsSheet`:** volume name, a list of snapshots (name, "Time Machine" or "Created by another app — delete it there"), and a "Delete" button per deletable row that runs `AdminRunner().run(deleteCommand)` and reloads. An empty state reads "No local snapshots on this disk." A footer note: "macOS removes Time Machine snapshots automatically after 24 hours."
  - **`PurgeAction.run(mountPath:)`:** `AdminRunner().run(Snapshots.purgeCommand(...))`. Then it refreshes volumes every 10 s for 2 min, updating the purgeable virtual node's size: set it to the new `purgeableBytes` via a new `FileTree.setVirtualSize(_ id: NodeID, _ size: UInt64)` that adjusts ancestors, plus a unit test `setVirtualSizeAdjustsAncestors` in `FileTreeTests`.
- [ ] **Step 6: Verify:** "Local Snapshots…" lists snapshots matching `tmutil listlocalsnapshots /`. Dragging "Purgeable space" into the Collector and pressing Delete prompts for the admin password, and then the purgeable size drops within a few minutes (7–10 GB residual is normal).
- [ ] **Step 7: Commit** `feat: local snapshots sheet and purgeable purge`

---

### Task 18: Rescan, Forget Results, app icon, final verification

**Files:**
- Modify: `Sources/MajesCore/FileTree.swift` (add `replaceSubtree`), `ResultsModel.swift`, `Commands.swift`, `NodeContextMenu.swift`, `ResultsView.swift`, `scripts/build-app.sh` (build the icon if missing)
- Create: `scripts/make-icon.swift`, `README.md`
- Test: extend `Tests/MajesCoreTests/FileTreeTests.swift`

**Interfaces:**
- Produces: `FileTree.replaceSubtree(of id: NodeID, with fresh: FileTree)`. It grafts `fresh`'s root children under `id`, marks the old children `.deleted` without touching ancestor sizes, applies the delta `fresh.size(root) − size(id)` up the chain, and re-sorts the ancestor lists. New nodes get IDs appended to the arena. Also `ResultsModel.rescanFolder()` and `rescanAll()`.

- [ ] **Step 1: Write the failing test** `replaceSubtreeSplicesAndAdjustsSizes`: sample tree (root 400, `a` = 300). Build a fresh tree for "/r/a" with files `x` 50 and `y` 25. After `replaceSubtree(of: a, with: fresh)`: `size(a) == 75`, `size(root) == 175`, `children(a)` names are `["x","y"]`, `node(atPath: "/r/a/g") == nil`, and `node(atPath: "/r/a/x") != nil`.
- [ ] **Step 2: Run** the test. Expected: FAIL. **Step 3:** implement. **Step 4:** run. Expected: PASS.
- [ ] **Step 5: Wire the rescans.**
  - ⌘R / "Rescan This Folder" runs `Scanner` on `tree.path(center)` (or the context-menu node) in the background, shows a small progress overlay on the map, then calls `replaceSubtree` and increments `treeVersion`.
  - ⇧⌘R / "Rescan Disk" calls `appModel.startScan(path: tree.rootPath, asAdministrator: <same as original>)`.
  - "Forget Scan Results" calls `appModel.showOverview()`, which drops the `ResultsModel` so its memory is freed.
- [ ] **Step 6: Write `scripts/make-icon.swift`.** It takes one argument, the output `.iconset` directory. For sizes 16, 32, 128, 256 and 512 at @1x and @2x, it draws a 3-ring rainbow sunburst with a white center on a rounded-rect dark background using CoreGraphics and writes the standard `icon_WxH[@2x].png` names. `build-app.sh` runs `swift scripts/make-icon.swift dist/AppIcon.iconset && iconutil -c icns dist/AppIcon.iconset -o Resources/AppIcon.icns` when `Resources/AppIcon.icns` is missing.
- [ ] **Step 7: Write `README.md`.** Cover build/test/run commands, how permissions work (FDA, admin via the password prompt, no daemon), the optional `MAJESDISK_SIGN_IDENTITY` for a stable TCC identity, and the scope differences from DaisyDisk (spec §3).
- [ ] **Step 8: Final verification.**
  - Run `scripts/test.sh`. Expected: all suites pass, 0 failures.
  - Run `scripts/build-app.sh release`. Expected: codesign verify passes.
  - With FDA granted, scan `/`. Expected: it finishes. The scanned total plus hidden space equals the overview's used figure to within 1%. The `/System/Volumes` folder shows only small non-mount content, with no Data-volume duplicate. Memory in Activity Monitor stays under ~150 bytes per scanned item.
  - ⌘R on `~/Downloads` after adding a file in Finder shows the new file without a full rescan.
  - Re-check the five Review Focus items manually against the running app.
- [ ] **Step 9: Commit** `feat: rescan, forget results, app icon, README`

**Milestone C gate:** everything is green and all spec requirements R1–R12 are demonstrably working.

---

## Requirement → Task map

| Req | Tasks |
|---|---|
| R1 Overview | 5, 8 |
| R2 Scanner | 2, 3, 4, 9 |
| R3 Map | 7, 10 |
| R4 Navigation/keys | 7, 10, 11 |
| R5 Quick Look / Finder / packages | 12 |
| R6 Collector / deletion | 13, 14 |
| R7 Hidden space | 5, 9, 11 |
| R8 Full Disk Access | 15 |
| R9 Admin scan/delete | 6, 16 |
| R10 Snapshots / purge | 17 |
| R11 Rescan / forget | 18 |
| R12 CLT build, signed .app | 1, 8, 18 |
