// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "redis-swift",
    platforms: [
        .macOS(.v10_14)
    ],
    products: [
        .library(name: "RedisCore", targets: ["RedisCore"]),
        .executable(name: "redis-swift", targets: ["redis-swift"])
    ],
    targets: [
        .target(
            name: "RedisCore"),
        .executableTarget(
            name: "redis-swift",
            dependencies: ["RedisCore"]),
        .testTarget(
            name: "RedisCoreTests",
            dependencies: ["RedisCore"])
    ]
)
