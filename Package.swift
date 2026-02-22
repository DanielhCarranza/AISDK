// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AISDK",
    // Version: 2.0.0-beta.1 - Comprehensive AI SDK for Swift
    // Release Date: February 17, 2026
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
        .tvOS(.v17)
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
        ),
        .executable(
            name: "OpenRouterDemo",
            targets: ["OpenRouterDemo"]
        ),
        // Comprehensive AISDK Demo - showcases all features
        .executable(
            name: "AISDKDemo",
            targets: ["AISDKDemo"]
        ),
        // AISDK Test Runner - real model testing and validation
        .executable(
            name: "AISDKTestRunner",
            targets: ["AISDKTestRunner"]
        ),
        // AISDK CLI - Interactive terminal AI assistant
        .executable(
            name: "AISDKCLI",
            targets: ["AISDKCLI"]
        ),
        // OpenAI Responses API Demo - tests Responses API adapter
        .executable(
            name: "ResponsesAPIDemo",
            targets: ["ResponsesAPIDemo"]
        ),
        // Smoke Test App - Layer 1 production validation
        .executable(
            name: "SmokeTestApp",
            targets: ["SmokeTestApp"]
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
        ),
        .executableTarget(
            name: "OpenRouterDemo",
            dependencies: ["AISDK"],
            path: "Examples/OpenRouterDemo"
        ),
        .executableTarget(
            name: "AISDKDemo",
            dependencies: ["AISDK"],
            path: "Examples/AISDKDemo"
        ),
        .executableTarget(
            name: "AISDKTestRunner",
            dependencies: ["AISDK"],
            path: "Examples/AISDKTestRunner"
        ),
        .executableTarget(
            name: "AISDKCLI",
            dependencies: ["AISDK"],
            path: "Examples/AISDKCLI"
        ),
        .executableTarget(
            name: "ResponsesAPIDemo",
            dependencies: ["AISDK"],
            path: "Examples/ResponsesAPIDemo"
        ),
        .executableTarget(
            name: "SmokeTestApp",
            dependencies: ["AISDK"],
            path: "Examples/SmokeTestApp"
        )
    ]
)
