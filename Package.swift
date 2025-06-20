// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AISDK",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v9),
        .tvOS(.v16)
    ],
    products: [
        // Core library - Required
        .library(
            name: "AISDK",
            targets: ["AISDK"]
        ),
        
        // Feature libraries - Optional
        // .library(
        //     name: "AISDKChat",
        //     targets: ["AISDKChat"]
        // ),
        
        // .library(
        //     name: "AISDKVoice",
        //     targets: ["AISDKVoice"]
        // ),
        
        // .library(
        //     name: "AISDKVision",
        //     targets: ["AISDKVision"]
        // ),
        
        // .library(
        //     name: "AISDKResearch", 
        //     targets: ["AISDKResearch"]
        // ),
        
        // Demo executables
        .executable(
            name: "BasicChatDemo",
            targets: ["BasicChatDemo"]
        ),
        .executable(
            name: "ToolDemo",
            targets: ["ToolDemo"]
        )
    ],
    dependencies: [
        // Network layer
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.8.0"),
        
        // JSON handling
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0"),
        
        // Markdown rendering for chat UI
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
        
        // Charts for data visualization
        .package(url: "https://github.com/danielgindi/Charts.git", from: "5.0.0"),
        
        // Vision/LiveKit support
        .package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.0.0")
    ],
    targets: [
        // MARK: - Core Target
        .target(
            name: "AISDK",
            dependencies: [
                "Alamofire",
                "SwiftyJSON"
            ],
            path: "Sources/AISDK",
            resources: [
                .process("Resources"),
                .copy("README.md"),
                .copy("docs")
            ]
        ),
        
        // MARK: - Feature Targets
        // .target(
        //     name: "AISDKChat",
        //     dependencies: [
        //         "AISDK",
        //         .product(name: "MarkdownUI", package: "swift-markdown-ui"),
        //         .product(name: "DGCharts", package: "Charts")
        //     ],
        //     path: "Sources/AISDKChat",
        //     resources: [
        //         .copy("README.md"),
        //         .copy("Tools/HealthTools.md")
        //     ]
        // ),
        
        // .target(
        //     name: "AISDKVoice",
        //     dependencies: ["AISDK"],
        //     path: "Sources/AISDKVoice",
        //     resources: [
        //         .copy("README.md")
        //     ]
        // ),
        
        // .target(
        //     name: "AISDKVision",
        //     dependencies: [
        //         "AISDK",
        //         .product(name: "LiveKit", package: "client-sdk-swift")
        //     ],
        //     path: "Sources/AISDKVision"
        // ),
        
        // .target(
        //     name: "AISDKResearch",
        //     dependencies: ["AISDK"],
        //     path: "Sources/AISDKResearch",
        //     resources: [
        //         .copy("ResearcherAgent.md")
        //     ]
        // ),
        
        // MARK: - Test Targets
        .testTarget(
            name: "AISDKTests",
            dependencies: ["AISDK"],
            path: "Tests/AISDKTests"
        ),
        
        // .testTarget(
        //     name: "AISDKChatTests",
        //     dependencies: ["AISDKChat"],
        //     path: "Tests/AISDKChatTests"
        // ),
        
        // .testTarget(
        //     name: "AISDKVoiceTests",
        //     dependencies: ["AISDKVoice"],
        //     path: "Tests/AISDKVoiceTests"
        // ),
        
        // .testTarget(
        //     name: "AISDKVisionTests",
        //     dependencies: ["AISDKVision"],
        //     path: "Tests/AISDKVisionTests"
        // ),
        
        // .testTarget(
        //     name: "AISDKResearchTests", 
        //     dependencies: ["AISDKResearch"],
        //     path: "Tests/AISDKResearchTests"
        // ),
        
        // MARK: - Demo Targets
        .executableTarget(
            name: "BasicChatDemo",
            dependencies: ["AISDK"],
            path: "Examples/BasicChatDemo"
        ),
        .executableTarget(
            name: "ToolDemo",
            dependencies: ["AISDK"],
            path: "Examples/ToolDemo"
        )
    ]
)
