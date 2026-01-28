//
//  CLITestRunner.swift
//  AISDKTests
//
//  Helper for running AISDK CLI commands in tests
//

import Foundation
import XCTest

struct CLITestRunner {

    struct CommandResult {
        let output: String
        let errorOutput: String
        let exitCode: Int32

        var succeeded: Bool { exitCode == 0 }
    }

    static func run(
        _ arguments: [String],
        input: String? = nil,
        timeout: TimeInterval = 120
    ) throws -> CommandResult {
        let process = Process()
        let resolution = resolveCommand(arguments: arguments)

        process.executableURL = resolution.executableURL
        process.arguments = resolution.arguments
        process.currentDirectoryURL = resolution.workingDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if let input = input {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        }

        process.environment = ProcessInfo.processInfo.environment

        try process.run()

        let timeoutWorkItem = DispatchWorkItem {
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

        process.waitUntilExit()
        timeoutWorkItem.cancel()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            output: String(data: outputData, encoding: .utf8) ?? "",
            errorOutput: String(data: errorData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    static func isAvailable() -> Bool {
        do {
            let result = try run(["--help"], timeout: 60)
            return result.succeeded
        } catch {
            return false
        }
    }

    private static func resolveCommand(arguments: [String]) -> (executableURL: URL, arguments: [String], workingDirectory: URL?) {
        let env = ProcessInfo.processInfo.environment

        if let cliPath = env["AISDK_CLI_PATH"], !cliPath.isEmpty {
            return (URL(fileURLWithPath: cliPath), arguments, nil)
        }

        if let buildDir = env["BUILD_DIR"], !buildDir.isEmpty {
            let candidate = URL(fileURLWithPath: buildDir).appendingPathComponent("AISDKCLI")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return (candidate, arguments, nil)
            }
        }

        let projectDir = env["AISDK_PROJECT_DIR"].map { URL(fileURLWithPath: $0) } ?? defaultProjectDirectory()
        let swiftURL = URL(fileURLWithPath: "/usr/bin/swift")
        let swiftArguments = ["run", "AISDKCLI"] + arguments

        return (swiftURL, swiftArguments, projectDir)
    }

    private static func defaultProjectDirectory() -> URL {
        var url = URL(fileURLWithPath: #file)
        for _ in 0..<3 {
            url = url.deletingLastPathComponent()
        }
        return url
    }
}
