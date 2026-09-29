// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacEspIDFtool",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MacEspIDFtool",
            path: "Sources/MacEspIDFtool",
            swiftSettings: [
                // 串口读取天然跨线程，使用 v5 语言模式降低严格并发检查噪音
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
