// swift-tools-version: 6.2
import PackageDescription

#if os(Linux)
let kubeCompassDependencies: [Package.Dependency] = [
    .package(
        url: "https://github.com/makoni/swift-adwaita.git",
        revision: "e725f39c4308138da251a8181beb0a40d86efea9"
    )
]
let kubeCompassProducts: [Product] = [
    .library(name: "KubeCompassCore", targets: ["KubeCompassCore"]),
    .executable(name: "kubecompass-trace", targets: ["KubeCompassTrace"]),
    .executable(name: "kubecompass-linux", targets: ["KubeCompassLinux"])
]
let kubeCompassTargets: [Target] = [
    .target(name: "KubeCompassCore", path: "Sources/KubeCompassCore"),
    .target(name: "KubeCompassLinuxSupport", path: "Sources/KubeCompassLinux/Support"),
    .executableTarget(
        name: "KubeCompassTrace",
        dependencies: ["KubeCompassCore"],
        path: "Sources/KubeCompassTrace"
    ),
    .executableTarget(
        name: "KubeCompassLinux",
        dependencies: [
            "KubeCompassCore",
            "KubeCompassLinuxSupport",
            .product(name: "Adwaita", package: "swift-adwaita")
        ],
        path: "Sources/KubeCompassLinux/App"
    ),
    .testTarget(
        name: "KubeCompassCoreTests",
        dependencies: ["KubeCompassCore"],
        path: "Tests/KubeCompassCoreTests"
    ),
    .testTarget(
        name: "KubeCompassLinuxTests",
        dependencies: ["KubeCompassLinuxSupport", "KubeCompassCore"],
        path: "Tests/KubeCompassLinuxTests"
    )
]
#else
let kubeCompassDependencies: [Package.Dependency] = []
let kubeCompassProducts: [Product] = [
    .library(name: "KubeCompassCore", targets: ["KubeCompassCore"]),
    .executable(name: "kubecompass-trace", targets: ["KubeCompassTrace"])
]
let kubeCompassTargets: [Target] = [
    .target(name: "KubeCompassCore", path: "Sources/KubeCompassCore"),
    .target(name: "KubeCompassLinuxSupport", path: "Sources/KubeCompassLinux/Support"),
    .executableTarget(
        name: "KubeCompassTrace",
        dependencies: ["KubeCompassCore"],
        path: "Sources/KubeCompassTrace"
    ),
    .testTarget(
        name: "KubeCompassCoreTests",
        dependencies: ["KubeCompassCore"],
        path: "Tests/KubeCompassCoreTests"
    ),
    .testTarget(
        name: "KubeCompassLinuxTests",
        dependencies: ["KubeCompassLinuxSupport", "KubeCompassCore"],
        path: "Tests/KubeCompassLinuxTests"
    )
]
#endif

let package = Package(
    name: "KubeCompass",
    products: kubeCompassProducts,
    dependencies: kubeCompassDependencies,
    targets: kubeCompassTargets
)
