import XCTest
@testable import AISDK

final class AnthropicSkillsTypesTests: XCTestCase {
    func testSkillConfigEncodingUsesSnakeCase() throws {
        let config = SkillConfig(skillId: "web-search", type: .anthropic, version: "1")
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["skill_id"] as? String, "web-search")
        XCTAssertEqual(json?["type"] as? String, "anthropic")
        XCTAssertEqual(json?["version"] as? String, "1")
    }

    func testMCPServerEncodingUsesSnakeCase() throws {
        let toolConfig = MCPToolConfiguration(enabled: true, allowedTools: ["calc"], blockedTools: ["secret"])
        let server = MCPServerConfig(
            name: "tools",
            url: "https://example.com/mcp",
            authorizationToken: "token",
            toolConfiguration: toolConfig
        )

        let data = try JSONEncoder().encode(server)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["authorization_token"] as? String, "token")
        let toolConfigJSON = json?["tool_configuration"] as? [String: Any]
        XCTAssertEqual(toolConfigJSON?["allowed_tools"] as? [String], ["calc"])
        XCTAssertEqual(toolConfigJSON?["blocked_tools"] as? [String], ["secret"])
    }

    func testContainerConvenienceBuilders() {
        let container = ContainerConfig.webSearch()
        XCTAssertEqual(container.skills.count, 1)
        XCTAssertEqual(container.skills.first?.skillId, AnthropicSkill.webSearch.rawValue)

        let multi = ContainerConfig.withSkills([.webSearch, .codeExecution])
        XCTAssertEqual(multi.skills.count, 2)
    }
}
