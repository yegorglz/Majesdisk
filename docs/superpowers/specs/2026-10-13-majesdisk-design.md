# MajesDisk — DaisyDisk-style Disk Analyzer: Research & Design Spec

Date: 2026-10-13 · Target: macOS 14+ (developed on macOS 26.5, Apple Silicon) · Toolchain: Swift 6.3 Command Line Tools (no Xcode)

MajesDisk recreates the standalone (non-App-Store) edition of DaisyDisk 4 (https://daisydiskapp.com, user guide https://daisydiskapp.com/guide/4/en/). The name, icon and bundle ID are our own; nothing ships with "DaisyDisk" branding.

## 1. What DaisyDisk does (research summary)

### 1.1 Disks overview (launch screen)
- Lists every mounted volume, startup disk first: internal/external, SSD/HDD, network, disk images.
- Each row: icon, name, a **usage gauge** (green when at least half is empty, turning to red as it fills), **free space** under the gauge (hover shows used). Values update in real time, before any scan.
- Purgeable space is counted as *free* on the gauge (matches Finder). Holding **⌥** shows the gauge with purgeable counted as *filled*.
- **Scan** button per disk with a drop-down: *Scan*, *Scan as Administrator*. Plus a **Scan Folder…** button. Dragging a disk or folder from Finder onto the window or Dock icon scans it.
- **Starred folders**: click a folder's icon to star it; it stays pinned in the list across launches.

### 1.2 Scanning
- Very fast (seconds on SSD). Parallel scanning; mechanical HDDs are scanned without parallel requests to avoid head thrashing.
- Sizes are **physical** (allocated blocks), not logical. HFS+/APFS-compressed files count at their compressed size.
- **Hard links** counted once: the first occurrence is primary; other links get a virtual size of 0. **Full APFS clones** handled the same way (macOS 14+). Partial clones are not deduplicated.
- **Packages** (.app, .photoslibrary…) appear as single objects; "Show Package Contents" expands them.
- Restricted folders (no permission) appear empty and of zero size, colored **purple**; their space lands in hidden space.
- Network volumes, Time Machine volumes and disk images are slower; mount points are not crossed.

### 1.3 The map (sunburst)
- Concentric rings: the center is the current folder; each ring outward is one level deeper. Segment angle is proportional to size. Children sorted by size, largest first.
- Colored segments = folders (hue varies around the circle), **grey** = files, **purple** = restricted, **semi-transparent** = "smaller objects" (items too thin to draw, merged into one petal).
- Hovering a folder shows its contents in the sidebar. Clicking a folder drills into it. Clicking the center goes up to the parent.
- The sidebar lists the hovered/current folder's items with sizes. "Smaller objects" expands into the full list there.
- Virtual item **Hidden space** = used space − scanned total, broken into **Purgeable space**, **Other volumes** (other APFS volumes in the same container), and **Still hidden** (other users' homes, Spotlight index, fs overhead).

### 1.4 Keyboard and gestures (from /guide/4/en/Hotkeys/)
| Action | Key |
|---|---|
| Previous / next item in current folder | ↑ / ↓ |
| Page up / page down | PgUp / PgDn |
| First / last item | Home / End |
| Go to enclosing folder | ⌘↑ (pinch close) |
| Back / forward in history | ⌘[ / ⌘] |
| Enter pointed folder / expand smaller objects | Return (pinch open) |
| Quick Look pointed item | Space |
| Move pointed item to/from Collector | ⌘⌫ |
| Reveal in Finder | ⌘-click |
| Rescan current folder / whole disk | ⌘R / ⇧⌘R |
| Gauge shows purgeable as filled | hold ⌥ |

### 1.5 Preview
- Space or context menu "Preview" opens **Quick Look** (same panel as Finder, so installed QL plugins apply). Works on map, sidebar and Collector items.

### 1.6 Collector and deletion
- Drag a segment or list row onto the **Collector** at the bottom of the window, or use ⌘⌫ or the context menu.
- The Collector refuses system-critical folders (`/System`, `/Library`, home folder…) with a message, and refuses "smaller objects" aggregates.
- Click the Collector to expand its list (preview, drag back out, × removes an item).
- **Delete** starts a **5-second countdown with Cancel**. Deletion is **permanent** (bypasses Trash so the space is actually freed). Items stay intact until Delete.
- The map updates after in-app deletion without a rescan. Freed space may move into purgeable when Time Machine snapshots hold it.
- If permissions are insufficient, deletion is retried with raised privileges.

### 1.7 Hidden/system space, snapshots, purgeable
- Purgeable = space macOS counts as available-for-important-usage but not free (mostly local Time Machine snapshots). Dragging **Purgeable space** to the Collector forces a purge (standalone edition only; takes minutes; ~7–10 GB residual is normal).
- Local APFS snapshots can be listed and deleted (standalone edition; App Store edition needs Terminal). Third-party snapshots (e.g. CCC) cannot be deleted by us.

### 1.8 Permissions DaisyDisk needs (and why)
| Permission | Why | How DaisyDisk handles it | MajesDisk decision |
|---|---|---|---|
| **No App Sandbox** | Must read the whole file system and run privileged tools | Standalone edition is not sandboxed. The App Store edition loses admin scan, purge and snapshot deletion | Not sandboxed; no entitlements file |
| **Full Disk Access (TCC)** | Without it, Mail, Messages, Safari, Photos, Containers… read as empty and land in hidden space; Desktop/Documents/Downloads/removable/network volumes trigger per-folder prompts | Preferences → Full Disk Access tab shows status and instructions; user adds the app in System Settings → Privacy & Security → Full Disk Access, then **relaunches** | Detect by probing a TCC-protected file; banner + Settings tab with an "Open System Settings" button (`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`); relaunch prompt |
| **Per-folder TCC usage strings** | Needed when FDA is not granted | — | `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription`, `NSNetworkVolumesUsageDescription` in Info.plist |
| **Administrator (root)** | Scan other users' homes and root-only system folders; delete root-owned files; purge and delete snapshots | Privileged launchd helper `com.daisydiskapp.DaisyDiskStandAlone.AdminHelper` installed in `/Library/PrivilegedHelperTools` and `/Library/LaunchDaemons` after an admin password prompt (SMJobBless-style); "Quick Rescan as Administrator" | **Per-action elevation via `osascript … with administrator privileges`** running our bundled `majes-helper` CLI. A persistent daemon (SMAppService) needs a Developer ID Team ID for reliable XPC client validation, which an ad-hoc-signed SwiftPM build does not have. Same user-visible result, no installed daemon |
| **Stable code signature** | TCC grants are tied to the code signature; an ad-hoc signature changes on every rebuild, which silently revokes FDA | Developer ID signed | Optional self-signed identity via `MAJESDISK_SIGN_IDENTITY`; ad-hoc otherwise, and FDA must be re-granted after each rebuild |

### 1.9 Verified low-level facts (probed on this Mac, 2026-10-13)
- `getattrlistbulk` buffer layout per entry: `u32 length`, `attribute_set_t returned` (20 bytes), then **`ATTR_CMN_ERROR` (u32) immediately after RETURNED_ATTRS**, then remaining common attrs in ascending bit order, then dir attrs, then file attrs, then extended (`forkattr` with `FSOPT_ATTR_CMN_EXTENDED`). Directory attrs are present only for directories and file attrs only for non-directories. Parse strictly by the `returned` bitmap. Fields are only 4-byte aligned, so use unaligned loads for 64-bit values.
- Under `/`: firmlinked folders (`/Users`, `/Applications`, `/Library`, `/private`) have `ATTR_DIR_MOUNTSTATUS == 0`. Real mount points (`/dev`, `/System/Volumes/Data`, `/System/Volumes/Preboot`, `/System/Volumes/VM`…) have `DIR_MNTSTATUS_MNTPOINT (1)`. **Rule: descend into everything except entries flagged as mount points** → the Data volume is counted once through firmlinks.
- Clone/hard-link dedupe: for a file `a`, its hard link `h` and its clone `b`, all three report `ATTR_CMNEXT_CLONEID == 1228327` (a's file ID). `a`/`h` have `LINKCOUNT 2`, and all have `CLONE_REFCNT 2`. **One dedupe key = cloneID (fallback fileID) when linkCount > 1 or cloneRefCount > 1.**
- 1,000,000-byte random file → `ATTR_FILE_ALLOCSIZE` 1,003,520 (4 KiB blocks). A 3-byte file → 4096.
- `diskutil apfs list -plist`: `Containers[].{ContainerReference, CapacityCeiling, CapacityFree, Volumes[].{Name, DeviceIdentifier, Roles[], CapacityInUse}}`. `diskutil info -plist /`: `DeviceIdentifier` (`disk3s1s1`, the sealed system snapshot), `APFSContainerReference` (`disk3`), `SolidState`, `Internal`, `FilesystemType`.
- `tmutil listlocalsnapshots /` prints `Snapshots for disk /:` then one name per line (`com.apple.TimeMachine.YYYY-MM-DD-HHMMSS.local`). Delete with `tmutil deletelocalsnapshots <YYYY-MM-DD-HHMMSS>` (root); force purge with `tmutil thinlocalsnapshots <mount> <bytes> 4` (root).

## 2. Requirements for MajesDisk

R1 Disks overview as in 1.1 (gauge thresholds: used ≤ 50% green, ≤ 85% orange, otherwise red; refresh every 2 s; ⌥ toggles purgeable-as-filled; starred folders persisted).
R2 Scanner as in 1.2 and 1.9: physical sizes, dedupe, packages, restricted flagging, mount-point skipping, parallel on SSD (8 workers), serial on HDD (1 worker), cancellable, progress ≥ 10 Hz.
R3 Sunburst map as in 1.3: 6 visible rings, merge segments thinner than 0.6° into "smaller objects", colors as specified in the plan, hover → sidebar, click → drill, center → up, animated transition (0.3 s).
R4 Navigation and keyboard as in 1.4, with back/forward history and breadcrumbs.
R5 Quick Look, Reveal in Finder (⌘-click and context menu), Copy Path, Show Package Contents.
R6 Collector and deletion as in 1.6. Default mode is permanent with a 5 s countdown. Setting: "Move to Trash instead".
R7 Hidden space breakdown (1.3, 1.7) for whole-volume scans.
R8 Full Disk Access detection and guidance (1.8).
R9 Scan as Administrator, plus "Delete as Administrator" retry, via the bundled helper (1.8).
R10 Local snapshots sheet (list; delete Time Machine ones as admin) and purgeable purge via Collector.
R11 Rescan current folder (⌘R) splices into the existing tree. Full rescan (⇧⌘R). "Forget Scan Results".
R12 Builds and tests with Command Line Tools only; produces a signed `MajesDisk.app`.

## 3. Out of scope
Cloud-drive scanning (Dropbox/Google Drive/OneDrive/Box APIs), licensing/trial, localization, App Store edition, snapshot size estimation, cross-window HDD scan queueing, "struck-out" detection of external changes, Sparkle updates.
