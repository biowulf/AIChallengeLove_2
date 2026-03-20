// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MCPDateServer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.106.0"),
    ],
    targets: [
        .executableTarget(
            name: "MCPDateHTTP",
            dependencies: [
                .product(name: "MCP",   package: "swift-sdk"),
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/MCPDateHTTP"
        ),
    ]
)
