import Foundation
import Testing
@testable import MajesCore

@Test func formatsDecimalLikeFinder() {
    let en = Locale(identifier: "en_US")
    #expect(ByteFormat.string(0, locale: en) == "Zero kB")
    #expect(ByteFormat.string(1_500_000_000, locale: en) == "1.5 GB")
    #expect(ByteFormat.string(52_428_800, locale: en) == "52.4 MB")
    #expect(ByteFormat.string(1_500_000_000, locale: Locale(identifier: "de_DE")).replacingOccurrences(of: "\u{00A0}", with: " ") == "1,5 GB")
}
