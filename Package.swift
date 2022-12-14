// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-ssh-client",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "SSHClient",
            targets: ["SSHClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh", from: "0.5.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "2.1.0"),
    ],
    targets: [
        .target(
            name: "SSHClient",
            dependencies: [
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "SSHClientTests",
            dependencies: ["SSHClient"]
        ),
    ]
)
