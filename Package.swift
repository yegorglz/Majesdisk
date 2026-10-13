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
