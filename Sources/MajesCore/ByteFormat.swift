import Foundation

public enum ByteFormat {
    /// Decimal units like Finder ("1.5 GB"), in the user's locale.
    public static func string(_ bytes: UInt64, locale: Locale = .current) -> String {
        Int64(clamping: bytes).formatted(.byteCount(style: .file).locale(locale))
    }
}
