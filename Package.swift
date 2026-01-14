// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "redis-swift",
    products: [
        .library(name: "RedisCore", targets: ["RedisCore"]),
        .library(name: "RedisServer", targets: ["RedisServer"]),
        .executable(name: "redis-swift", targets: ["redis-swift"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.66.0")
    ],
    targets: [
        .target(
            name: "RedisCore"),
        .target(
            name: "RedisServer",
            dependencies: [
                "RedisCore",
                .product(name: "NIO", package: "swift-nio")
            ]),
        .executableTarget(
            name: "redis-swift",
            dependencies: ["RedisServer"]),
        .testTarget(
            name: "RedisCoreTests",
            dependencies: ["RedisCore"])
    ]
)
