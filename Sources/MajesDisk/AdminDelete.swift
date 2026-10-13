import Foundation
import MajesCore

extension ResultsModel {
    /// Retries permission-denied deletions through `majes-helper delete` as root.
    func deleteAsAdministrator(_ paths: [String]) {
        let ids = Dictionary(uniqueKeysWithValues: paths.compactMap { p in tree.node(atPath: p).map { (p, $0) } })
        Task {
            do {
                let output = try await AdminRunner(prompt: "MajesDisk wants to delete items that need administrator access.")
                    .run([Helper.path, "delete", "--home", NSHomeDirectory()] + paths)
                let outcomes = output.split(whereSeparator: \.isNewline).compactMap { line -> DeleteOutcome? in
                    guard let r = try? JSONDecoder().decode(HelperDeleteResult.self, from: Data(line.utf8)) else { return nil }
                    let failure: DeleteFailure? = switch r.error {
                    case nil: nil
                    case "protected": .protected("This item is protected.")
                    case "notFound": .notFound
                    case "permissionDenied": .permissionDenied
                    case let m?: .other(m)
                    }
                    return DeleteOutcome(path: r.path, failure: failure)
                }
                applyDeletions(outcomes.map { o in
                    var o = o
                    if o.failure == .permissionDenied { o.failure = .other("still not permitted (System Integrity Protection?)") }
                    return o
                }, ids: ids)
            } catch AdminRunnerError.cancelled {
            } catch {
                alert = AlertInfo(title: "Delete as Administrator failed", message: "\(error)")
            }
        }
    }
}
