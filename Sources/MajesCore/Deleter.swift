import Foundation

public enum DeleteMode: String, Sendable { case permanent, moveToTrash }
public enum DeleteFailure: Error, Equatable, Sendable { case protected(String), notFound, permissionDenied, other(String) }
public struct DeleteOutcome: Sendable, Equatable {
    public var path: String
    public var failure: DeleteFailure?
    public init(path: String, failure: DeleteFailure?) { self.path = path; self.failure = failure }
}

/// Deletes items, re-checking protection right before each one. Symlinks are removed, never followed.
public enum Deleter {
    public static func delete(paths: [String], mode: DeleteMode, verdict: (String) -> ProtectionVerdict) -> [DeleteOutcome] {
        paths.map { path in
            if case .protected(let why) = verdict(path) { return DeleteOutcome(path: path, failure: .protected(why)) }
            var st = stat()
            guard lstat(path, &st) == 0 else { return DeleteOutcome(path: path, failure: .notFound) }
            do {
                switch mode {
                case .permanent: try FileManager.default.removeItem(atPath: path)
                case .moveToTrash: try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                }
                return DeleteOutcome(path: path, failure: nil)
            } catch {
                return DeleteOutcome(path: path, failure: classify(error))
            }
        }
    }

    static func classify(_ error: Error) -> DeleteFailure {
        let ns = error as NSError
        let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? Int32($0.code) : nil }
        if ns.code == NSFileNoSuchFileError || posix == ENOENT { return .notFound }
        if ns.code == NSFileWriteNoPermissionError || posix == EACCES || posix == EPERM { return .permissionDenied }
        return .other(ns.localizedDescription)
    }
}
