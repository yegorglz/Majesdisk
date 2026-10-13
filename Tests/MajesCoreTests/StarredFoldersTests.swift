import Foundation
import Testing
@testable import MajesCore

@Test func starredFoldersPersist() {
    let d = UserDefaults(suiteName: "test-\(UUID())")!
    let s = StarredFolders(defaults: d)
    s.add("/a"); s.add("/a"); s.add("/b")
    #expect(StarredFolders(defaults: d).paths == ["/a", "/b"])
    #expect(s.contains("/b"))
    s.remove("/a")
    #expect(StarredFolders(defaults: d).paths == ["/b"])
}
