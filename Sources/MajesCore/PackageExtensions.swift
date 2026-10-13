/// Folders macOS presents as single documents or apps.
public enum PackageExtensions {
    static let all: Set<String> = [
        "app", "bundle", "framework", "plugin", "appex", "kext", "xpc", "photoslibrary", "photolibrary",
        "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "band", "xcodeproj",
        "xcworkspace", "xcarchive", "playground", "rtfd", "pages", "numbers", "key", "mdimporter",
        "qlgenerator", "prefpane", "saver", "component", "vst", "vst3", "aaxplugin", "dsym",
    ]
    public static func isPackage(name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return all.contains(name[name.index(after: dot)...].lowercased())
    }
}
