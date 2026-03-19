// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MCPServer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.106.0"),
    ],
    targets: [
        .target(
            name: "GitTools",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/GitTools"
        ),
        .target(
            name: "SchedulerTools",
            dependencies: [
                "GitTools",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/SchedulerTools",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "MCPGitStdio",
            dependencies: [
                "GitTools",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/MCPGitStdio"
        ),
        .executableTarget(
            name: "MCPGitHTTP",
            dependencies: [
                "GitTools",
                "SchedulerTools",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/MCPGitHTTP"
        ),
        .executableTarget(
            name: "MCPGitClient",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/MCPGitClient"
        ),
    ]
)