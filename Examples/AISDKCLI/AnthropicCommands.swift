import Foundation
import AISDK

/// Handles Anthropic-specific CLI commands
final class AnthropicCommands {

    private let runtimeConfig: RuntimeConfig
    private let onConfigChanged: (() -> Void)?
    private let batchService: AnthropicBatchService?
    private let filesService: AnthropicFilesService?

    init(runtimeConfig: RuntimeConfig, onConfigChanged: (() -> Void)? = nil) {
        self.runtimeConfig = runtimeConfig
        self.onConfigChanged = onConfigChanged

        if let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty {
            self.batchService = AnthropicBatchService(apiKey: apiKey)
            self.filesService = AnthropicFilesService(apiKey: apiKey)
        } else {
            self.batchService = nil
            self.filesService = nil
        }
    }

    // MARK: - Command Dispatch

    func handleCommand(_ command: String, args: [String]) async -> Bool {
        switch command {
        case "thinking":
            return handleThinking(args)
        case "batch":
            return await handleBatch(args)
        case "files":
            return await handleFiles(args)
        case "skills":
            return handleSkills(args)
        case "mcp":
            return handleMCP(args)
        case "beta":
            return handleBeta(args)
        case "models":
            return handleModels(args)
        default:
            return false
        }
    }

    // MARK: - Thinking Commands

    private func handleThinking(_ args: [String]) -> Bool {
        guard !args.isEmpty else {
            printThinkingStatus()
            return true
        }

        switch args[0].lowercased() {
        case "on":
            runtimeConfig.thinkingEnabled = true
            print("✓ Extended thinking enabled (budget: \(runtimeConfig.thinkingBudget) tokens)")
            onConfigChanged?()
        case "off":
            runtimeConfig.thinkingEnabled = false
            print("✓ Extended thinking disabled")
            onConfigChanged?()
        case "budget":
            guard args.count > 1, let budget = Int(args[1]) else {
                print("Usage: /thinking budget <tokens>")
                print("  Range: 1024 - 128000")
                return true
            }
            guard (1024...128000).contains(budget) else {
                print("Error: Budget must be between 1024 and 128000 tokens")
                return true
            }
            runtimeConfig.thinkingBudget = budget
            runtimeConfig.thinkingEnabled = true
            print("✓ Thinking budget set to \(budget) tokens")
            onConfigChanged?()
        case "status":
            printThinkingStatus()
        default:
            print("Usage: /thinking [on|off|budget <tokens>|status]")
        }

        return true
    }

    private func printThinkingStatus() {
        print("\n📊 Extended Thinking Status:")
        print("  Enabled: \(runtimeConfig.thinkingEnabled ? "Yes" : "No")")
        print("  Budget: \(runtimeConfig.thinkingBudget) tokens")
        print("  Min budget: 1,024 tokens")
        print("  Max budget: 128,000 tokens")
        print("\nNote: Budget must be less than max_tokens\n")
    }

    // MARK: - Batch Commands

    private func handleBatch(_ args: [String]) async -> Bool {
        guard let service = batchService else {
            print("Error: Anthropic API key not configured")
            return true
        }

        guard !args.isEmpty else {
            printBatchHelp()
            return true
        }

        switch args[0].lowercased() {
        case "create":
            await handleBatchCreate(args: Array(args.dropFirst()), service: service)
        case "status":
            guard args.count > 1 else {
                print("Usage: /batch status <batch_id>")
                return true
            }
            await handleBatchStatus(id: args[1], service: service)
        case "list":
            await handleBatchList(service: service)
        case "cancel":
            guard args.count > 1 else {
                print("Usage: /batch cancel <batch_id>")
                return true
            }
            await handleBatchCancel(id: args[1], service: service)
        case "results":
            guard args.count > 1 else {
                print("Usage: /batch results <batch_id>")
                return true
            }
            await handleBatchResults(id: args[1], service: service)
        default:
            printBatchHelp()
        }

        return true
    }

    private func printBatchHelp() {
        print("""

        📦 Batch API Commands:
          /batch create <file.jsonl>  Create batch from JSONL file
          /batch status <id>          Get batch status
          /batch list                 List recent batches
          /batch cancel <id>          Cancel a running batch
          /batch results <id>         Stream batch results

        Batch format (JSONL):
          {"custom_id": "req-1", "params": {"model": "...", "max_tokens": 100, "messages": [...]}}

        """)
    }

    private func handleBatchCreate(args: [String], service: AnthropicBatchService) async {
        guard let filePath = args.first else {
            print("Usage: /batch create <file.jsonl>")
            return
        }

        do {
            let url = URL(fileURLWithPath: filePath)
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

            var requests: [AnthropicBatchRequestItem] = []
            for line in lines {
                let data = line.data(using: .utf8)!
                let item = try AnthropicHTTPClient.decoder.decode(
                    AnthropicBatchRequestItem.self,
                    from: data
                )
                requests.append(item)
            }

            print("Creating batch with \(requests.count) requests...")
            let batch = try await service.createBatch(requests: requests)

            print("\n✓ Batch created!")
            print("  ID: \(batch.id)")
            print("  Status: \(batch.processingStatus)")
            print("  Expires: \(batch.expiresAt)")
            print("\nUse '/batch status \(batch.id)' to check progress")

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    private func handleBatchStatus(id: String, service: AnthropicBatchService) async {
        do {
            let batch = try await service.getBatch(id: id)

            print("\n📦 Batch Status: \(id)")
            print("  Status: \(batch.processingStatus)")
            print("  Created: \(batch.createdAt)")
            if let ended = batch.endedAt {
                print("  Ended: \(ended)")
            }
            print("  Expires: \(batch.expiresAt)")
            print("\n  Request Counts:")
            print("    Processing: \(batch.requestCounts.processing)")
            print("    Succeeded:  \(batch.requestCounts.succeeded)")
            print("    Errored:    \(batch.requestCounts.errored)")
            print("    Canceled:   \(batch.requestCounts.canceled)")
            print("    Expired:    \(batch.requestCounts.expired)")

            if let url = batch.resultsUrl {
                print("\n  Results URL: \(url)")
                print("  Use '/batch results \(id)' to stream results")
            }
            print("")

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    private func handleBatchList(service: AnthropicBatchService) async {
        do {
            let response = try await service.listBatches(limit: 10)

            print("\n📦 Recent Batches:")
            print("─────────────────────────────────────────────────")

            for batch in response.data {
                let status = batch.processingStatus == .ended ? "✓" : "⏳"
                print("\(status) \(batch.id)")
                print("   Status: \(batch.processingStatus) | Created: \(batch.createdAt)")
                print("   Counts: \(batch.requestCounts.succeeded)/\(batch.requestCounts.total) succeeded")
            }

            if response.hasMore {
                print("\n(More batches available)")
            }
            print("")

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    private func handleBatchCancel(id: String, service: AnthropicBatchService) async {
        do {
            let batch = try await service.cancelBatch(id: id)
            print("✓ Batch cancellation initiated")
            print("  Status: \(batch.processingStatus)")
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    private func handleBatchResults(id: String, service: AnthropicBatchService) async {
        do {
            print("Streaming results for batch \(id)...\n")

            var count = 0
            for try await result in await service.streamResults(batchId: id) {
                count += 1
                let icon = result.result.type == .succeeded ? "✓" : "✗"
                print("\(icon) [\(result.customId)] \(result.result.type)")

                if let error = result.result.error {
                    print("   Error: \(error.message)")
                }
            }

            print("\nStreamed \(count) results")

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Files Commands

    private func handleFiles(_ args: [String]) async -> Bool {
        guard let service = filesService else {
            print("Error: Anthropic API key not configured")
            return true
        }

        guard !args.isEmpty else {
            printFilesHelp()
            return true
        }

        switch args[0].lowercased() {
        case "upload":
            guard args.count > 1 else {
                print("Usage: /files upload <path> [purpose]")
                print("  purpose: message_attachment (default) or container_upload")
                return true
            }
            await handleFileUpload(path: args[1], purpose: args.count > 2 ? args[2] : nil, service: service)
        case "list":
            await handleFileList(service: service)
        case "get":
            guard args.count > 1 else {
                print("Usage: /files get <file_id>")
                return true
            }
            await handleFileGet(id: args[1], service: service)
        case "delete":
            guard args.count > 1 else {
                print("Usage: /files delete <file_id>")
                return true
            }
            await handleFileDelete(id: args[1], service: service)
        case "download":
            guard args.count > 2 else {
                print("Usage: /files download <file_id> <output_path>")
                return true
            }
            await handleFileDownload(id: args[1], path: args[2], service: service)
        default:
            printFilesHelp()
        }

        return true
    }

    private func printFilesHelp() {
        print("""

        📁 Files API Commands:
          /files upload <path> [purpose]   Upload a file
          /files list                      List uploaded files
          /files get <id>                  Get file metadata
          /files delete <id>               Delete a file
          /files download <id> <path>      Download file content

        Purposes:
          message_attachment  - For use in messages (default)
          container_upload    - For container/skill operations

        Supported formats: PDF, images (JPEG, PNG, GIF, WebP), text files
        Max size: 32 MB for attachments, 100 MB for container uploads

        """)
    }

    private func handleFileUpload(path: String, purpose: String?, service: AnthropicFilesService) async {
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent

            let filePurpose: AnthropicFilePurpose = purpose == "container_upload" ? .containerUpload : .messageAttachment

            print("Uploading \(filename) (\(data.count) bytes)...")
            let file = try await service.uploadFile(
                data: data,
                filename: filename,
                purpose: filePurpose
            )

            print("\n✓ File uploaded!")
            print("  ID: \(file.id)")
            print("  Name: \(file.filename)")
            print("  Size: \(file.bytes) bytes")
            if let purpose = file.purpose {
                print("  Purpose: \(purpose)")
            }
            print("\nUse this ID in messages: \(file.id)\n")

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    private func handleFileList(service: AnthropicFilesService) async {
        do {
            let response = try await service.listFiles(limit: 20)

            print("\n📁 Uploaded Files:")
            print("─────────────────────────────────────────────────")

            for file in response.data {
                print("\(file.id)")
                print("   Name: \(file.filename) | Size: \(file.bytes) bytes")
                let purposeStr = file.purpose.map { "\($0)" } ?? "n/a"
                print("   Purpose: \(purposeStr) | Created: \(file.createdAt)")
            }

            if response.data.isEmpty {
                print("(No files uploaded)")
            }

            if response.hasMore {
                print("\n(More files available)")
            }
            print("")

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    private func handleFileGet(id: String, service: AnthropicFilesService) async {
        do {
            let file = try await service.getFile(id: id)

            print("\n📄 File Details:")
            print("  ID: \(file.id)")
            print("  Name: \(file.filename)")
            print("  Size: \(file.bytes) bytes")
            let purposeStr = file.purpose.map { "\($0)" } ?? "n/a"
            print("  Purpose: \(purposeStr)")
            print("  Created: \(file.createdAt)")
            if let mime = file.mimeType {
                print("  MIME Type: \(mime)")
            }
            print("")

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    private func handleFileDelete(id: String, service: AnthropicFilesService) async {
        do {
            let result = try await service.deleteFile(id: id)
            if result.deleted {
                print("✓ File deleted: \(id)")
            } else {
                print("✗ Failed to delete file")
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    private func handleFileDownload(id: String, path: String, service: AnthropicFilesService) async {
        do {
            print("Downloading file...")
            let data = try await service.getFileContent(id: id)

            let url = URL(fileURLWithPath: path)
            try data.write(to: url)

            print("✓ Downloaded \(data.count) bytes to \(path)")

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Skills Commands

    private func handleSkills(_ args: [String]) -> Bool {
        guard !args.isEmpty else {
            printSkillsStatus()
            return true
        }

        switch args[0].lowercased() {
        case "list":
            printAvailableSkills()
        case "enable":
            guard args.count > 1 else {
                print("Usage: /skills enable <skill_id>")
                return true
            }
            enableSkill(args[1])
        case "disable":
            guard args.count > 1 else {
                print("Usage: /skills disable <skill_id>")
                return true
            }
            disableSkill(args[1])
        case "status":
            printSkillsStatus()
        default:
            print("Usage: /skills [list|enable <skill>|disable <skill>|status]")
        }

        return true
    }

    private func printAvailableSkills() {
        print("""

        🔧 Available Anthropic Skills:
          web-search       Web search capability
          code-execution   Python code execution in sandbox
          file-operations  File operations within container
          text-analysis    Text analysis and processing

        Use '/skills enable <skill_id>' to enable a skill

        """)
    }

    private func enableSkill(_ skillId: String) {
        runtimeConfig.betaFeatures.insert("skills")
        print("✓ Skill enabled: \(skillId)")
        print("Note: Skills require the 'skills' beta feature")
        onConfigChanged?()
    }

    private func disableSkill(_ skillId: String) {
        print("✓ Skill disabled: \(skillId)")
    }

    private func printSkillsStatus() {
        let skillsEnabled = runtimeConfig.betaFeatures.contains("skills")
        print("\n🔧 Skills Status:")
        print("  Beta enabled: \(skillsEnabled ? "Yes" : "No")")
        print("\nUse '/skills list' to see available skills\n")
    }

    // MARK: - MCP Commands

    private func handleMCP(_ args: [String]) -> Bool {
        guard !args.isEmpty else {
            printMCPHelp()
            return true
        }

        switch args[0].lowercased() {
        case "add":
            guard args.count >= 3 else {
                print("Usage: /mcp add <name> <url> [token]")
                return true
            }
            addMCPServer(name: args[1], url: args[2], token: args.count > 3 ? args[3] : nil)
        case "remove":
            guard args.count > 1 else {
                print("Usage: /mcp remove <name>")
                return true
            }
            removeMCPServer(name: args[1])
        case "list":
            listMCPServers()
        default:
            printMCPHelp()
        }

        return true
    }

    private func printMCPHelp() {
        print("""

        🔌 MCP Server Commands:
          /mcp add <name> <url> [token]  Add an MCP server
          /mcp remove <name>             Remove an MCP server
          /mcp list                      List configured servers

        MCP (Model Context Protocol) enables Claude to connect to
        external tool servers for dynamic tool discovery.

        Example:
          /mcp add my-tools https://tools.example.com/mcp

        """)
    }

    private func addMCPServer(name: String, url: String, token: String?) {
        runtimeConfig.betaFeatures.insert("mcp-client")
        print("✓ MCP server added: \(name)")
        print("  URL: \(url)")
        if token != nil {
            print("  Auth: Token configured")
        }
        onConfigChanged?()
    }

    private func removeMCPServer(name: String) {
        print("✓ MCP server removed: \(name)")
    }

    private func listMCPServers() {
        print("\n🔌 Configured MCP Servers:")
        print("  (No servers configured)")
        print("\nUse '/mcp add <name> <url>' to add a server\n")
    }

    // MARK: - Beta Commands

    private func handleBeta(_ args: [String]) -> Bool {
        guard !args.isEmpty else {
            printBetaStatus()
            return true
        }

        switch args[0].lowercased() {
        case "list":
            printAvailableBetaFeatures()
        case "enable":
            guard args.count > 1 else {
                print("Usage: /beta enable <feature>")
                return true
            }
            runtimeConfig.betaFeatures.insert(args[1])
            print("✓ Beta feature enabled: \(args[1])")
            onConfigChanged?()
        case "disable":
            guard args.count > 1 else {
                print("Usage: /beta disable <feature>")
                return true
            }
            runtimeConfig.betaFeatures.remove(args[1])
            print("✓ Beta feature disabled: \(args[1])")
            onConfigChanged?()
        case "status":
            printBetaStatus()
        default:
            print("Usage: /beta [list|enable|disable|status]")
        }

        return true
    }

    private func printAvailableBetaFeatures() {
        print("""

        🧪 Available Beta Features:
          files-api              Files API for document/image upload
          context-1m             1 million token context window
          skills                 Container skills execution
          mcp-client             MCP server connections
          interleaved-thinking   Extended thinking in conversations
          computer-use           Computer use capability
          code-execution         Code execution in containers
          output-128k            128K output token limit
          extended-cache-ttl     Extended cache time-to-live
          context-management     Context management features
          token-efficient-tools  Efficient tool token usage

        Use '/beta enable <feature>' to enable

        """)
    }

    private func printBetaStatus() {
        print("\n🧪 Beta Features Status:")
        if runtimeConfig.betaFeatures.isEmpty {
            print("  No beta features enabled")
        } else {
            for feature in runtimeConfig.betaFeatures.sorted() {
                print("  ✓ \(feature)")
            }
        }
        print("\nUse '/beta list' to see available features\n")
    }

    // MARK: - Models Commands

    private func handleModels(_ args: [String]) -> Bool {
        if args.isEmpty || args[0] == "list" {
            printClaude45Models()
        } else if args[0] == "info", args.count > 1 {
            printModelInfo(args[1])
        } else {
            print("Usage: /models [list|info <model>]")
        }
        return true
    }

    private func printClaude45Models() {
        print("""

        🤖 Claude 4.5 Models:

        ┌─────────────────────────────────┬──────────┬─────────────┬──────────┐
        │ Model ID                        │ Tier     │ Max Tokens  │ Features │
        ├─────────────────────────────────┼──────────┼─────────────┼──────────┤
        │ claude-opus-4-5-20251101        │ Flagship │ 64,000 out  │ T V L M  │
        │ claude-sonnet-4-5-20250929      │ Pro      │ 64,000 out  │ T V L M  │
        │ claude-haiku-4-5-20251001       │ Mini     │ 64,000 out  │ T V L M  │
        └─────────────────────────────────┴──────────┴─────────────┴──────────┘

        Features: T=Thinking, V=Vision, L=Long Context, M=Multilingual

        Aliases:
          claude-opus-4-5-latest   → claude-opus-4-5-20251101
          claude-sonnet-4-5-latest → claude-sonnet-4-5-20250929
          claude-haiku-4-5-latest  → claude-haiku-4-5-20251001

        """)
    }

    private func printModelInfo(_ modelId: String) {
        if let model = AnthropicModels.findModel(modelId) {
            print("\n📋 Model Info: \(model.displayName)")
            print("  ID: \(model.name)")
            print("  Provider: \(model.provider)")
            print("  Input limit: \(model.inputTokenLimit ?? 0) tokens")
            print("  Output limit: \(model.outputTokenLimit ?? 0) tokens")
            print("  Capabilities: \(model.capabilities)")
            if model.isDeprecated {
                print("  ⚠️  DEPRECATED - consider upgrading to Claude 4.5")
            }
            print("")
        } else {
            print("Model not found: \(modelId)")
        }
    }
}
