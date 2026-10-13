# MajesDisk

A free, local, native macOS disk-space analyzer, modeled on DaisyDisk 4 (standalone edition):
disks overview with live gauges, a fast parallel scanner that measures physical size, an interactive
sunburst map, Quick Look, a Collector with safe deletion, hidden/purgeable space, local snapshots,
and Scan/Delete as Administrator. No network access, no telemetry.

Requires macOS 14+. Builds with the Xcode **Command Line Tools** alone (Swift 6.x); Xcode is optional.

## Build, test, run

```bash
scripts/test.sh                 # unit tests (Swift Testing; adds the CLT framework paths)
scripts/build-app.sh release    # → dist/MajesDisk.app (signed, hardened runtime)
scripts/run.sh --scan ~/Downloads   # debug build, launched via `open`, optionally straight into a scan
```

Launch through `open` (as `run.sh` does) so macOS attributes file access to MajesDisk, not to Terminal.

## Permissions

| What | Why | How |
|---|---|---|
| Not sandboxed | must read the whole disk and run privileged tools | no entitlements file |
| **Full Disk Access** | without it, Mail, Messages, Safari, app containers… read as empty and land in "hidden space" | the overview shows a banner; System Settings › Privacy & Security › Full Disk Access › enable MajesDisk, then **Relaunch** |
| Folder prompts | when FDA is off, macOS asks per folder (Desktop, Documents, Downloads, removable/network volumes) | usage strings are in `Resources/Info.plist` |
| Administrator | other users' homes, root-only folders, deleting root-owned files, purging, deleting snapshots | each action asks for your password via the standard macOS prompt and runs the bundled `Contents/Helpers/majes-helper` as root. Nothing is installed: no launch daemon, no background item |

**Signing and TCC:** macOS ties Full Disk Access to the app's code signature. Ad-hoc builds (the default)
get a new identity on every rebuild, so grant access again after rebuilding, or sign with your own identity:

```bash
MAJESDISK_SIGN_IDENTITY="My Code Signing Cert" scripts/build-app.sh release
```

If protected folders still read as empty during an administrator scan, also add
`MajesDisk.app/Contents/Helpers/majes-helper` to the Full Disk Access list.

## How sizes are counted

Physical allocated size (`ATTR_FILE_ALLOCSIZE` via `getattrlistbulk`), like DaisyDisk: compressed files
count at their compressed size, and hard links and full APFS clones count once. Packages (.app, .photoslibrary…)
show as single items (context menu › Show Package Contents). Mount points are not crossed; on the startup
disk the Data volume is reached through its firmlinks, so it is counted exactly once.

**Hidden space** = used space − scanned total, split into *Purgeable space*, *Other volumes* (sibling APFS
volumes) and *Still hidden*.

## Keyboard

↑/↓ PgUp/PgDn Home/End select · ↩ open · ⌘↑ enclosing folder · ⌘[ / ⌘] back/forward · Space Quick Look ·
⌘⌫ to/from Collector · ⌘-click reveal in Finder · ⌘R rescan folder · ⇧⌘R rescan disk · hold ⌥ on the overview
to count purgeable space as used. Pinch in/out on the map to enter/leave folders.

## Deleting

Drag items (or ⌘⌫) to the Collector at the bottom, then **Delete**. A 5-second countdown lets you cancel.
By default items are deleted permanently (space is freed now). Settings › General can switch to *Move to Trash*.
System and account folders (`/System`, `/Library`, your home, Desktop/Documents/Downloads, volume roots…)
are refused by the app and again by the helper.

## Differences from DaisyDisk

Not included: cloud-drive scanning (Dropbox, Google Drive, OneDrive, Box), licensing, localization,
snapshot size estimates, cross-window HDD scan queueing, struck-out detection of external changes,
dragging items back out of the Collector (use × instead).

## Debug flags

`--scan <path> [--admin]`, `--snapshot <png> --snapshot-delay <s>` (saves the app's own window),
`--collect <path>` / `--delete-collected`, `--debug-no-elevation`. See `scripts/snapshot.sh`.
