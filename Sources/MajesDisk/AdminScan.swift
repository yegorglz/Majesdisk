import MajesCore

extension ScanSession {
    func startAdministratorScan() { finish(.failed("Scanning as administrator is not available yet.")) }
    func cancelAdministratorScan() {}
}
