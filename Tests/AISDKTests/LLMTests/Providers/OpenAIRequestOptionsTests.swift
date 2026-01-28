//
//  OpenAIRequestOptionsTests.swift
//  AISDKTests
//
//  Tests for OpenAI Responses API request options
//

import XCTest
@testable import AISDK

final class OpenAIRequestOptionsTests: XCTestCase {

    // MARK: - Factory Methods Tests

    func testWithWebSearch_DefaultConfig() {
        let options = OpenAIRequestOptions.withWebSearch()

        XCTAssertNotNil(options.webSearch)
        XCTAssertTrue(options.webSearch?.enabled ?? false)
        XCTAssertEqual(options.webSearch?.searchContextSize, .medium)
        XCTAssertNil(options.fileSearch)
        XCTAssertNil(options.codeInterpreter)
    }

    func testWithWebSearch_CustomConfig() {
        let options = OpenAIRequestOptions.withWebSearch(
            searchContextSize: .high,
            userLocation: UserLocation(country: "US", region: "CA", city: "San Francisco")
        )

        XCTAssertNotNil(options.webSearch)
        XCTAssertTrue(options.webSearch?.enabled ?? false)
        XCTAssertEqual(options.webSearch?.searchContextSize, .high)
        XCTAssertEqual(options.webSearch?.userLocation?.city, "San Francisco")
        XCTAssertEqual(options.webSearch?.userLocation?.country, "US")
    }

    func testWithFileSearch_SingleVectorStore() {
        let options = OpenAIRequestOptions.withFileSearch(vectorStoreIds: ["vs_123"])

        XCTAssertNotNil(options.fileSearch)
        XCTAssertTrue(options.fileSearch?.enabled ?? false)
        XCTAssertEqual(options.fileSearch?.vectorStoreIds, ["vs_123"])
        XCTAssertNil(options.webSearch)
    }

    func testWithFileSearch_MultipleVectorStores() {
        let options = OpenAIRequestOptions.withFileSearch(
            vectorStoreIds: ["vs_123", "vs_456"],
            maxNumResults: 20
        )

        XCTAssertNotNil(options.fileSearch)
        XCTAssertEqual(options.fileSearch?.vectorStoreIds.count, 2)
        XCTAssertEqual(options.fileSearch?.maxNumResults, 20)
    }

    func testWithCodeInterpreter_Enabled() {
        let options = OpenAIRequestOptions.withCodeInterpreter()

        XCTAssertNotNil(options.codeInterpreter)
        XCTAssertTrue(options.codeInterpreter?.enabled ?? false)
        XCTAssertNil(options.webSearch)
        XCTAssertNil(options.fileSearch)
    }

    func testWithCodeInterpreter_WithContainer() {
        let options = OpenAIRequestOptions.withCodeInterpreter(containerId: "cntr_abc123")

        XCTAssertNotNil(options.codeInterpreter)
        XCTAssertTrue(options.codeInterpreter?.enabled ?? false)
        XCTAssertEqual(options.codeInterpreter?.containerId, "cntr_abc123")
    }

    func testWithReasoning_DefaultEffort() {
        let options = OpenAIRequestOptions.withReasoning()

        XCTAssertNotNil(options.reasoning)
        XCTAssertEqual(options.reasoning?.effort, .medium)
    }

    func testWithReasoning_HighEffort() {
        let options = OpenAIRequestOptions.withReasoning(effort: .high)

        XCTAssertNotNil(options.reasoning)
        XCTAssertEqual(options.reasoning?.effort, .high)
    }

    func testWithReasoning_SummaryEnabled() {
        let options = OpenAIRequestOptions.withReasoning(effort: .low, summary: .auto)

        XCTAssertNotNil(options.reasoning)
        XCTAssertEqual(options.reasoning?.effort, .low)
        XCTAssertEqual(options.reasoning?.summary, .auto)
    }

    // MARK: - Combining Options Tests

    func testCombiningOptions_WebSearchAndCodeInterpreter() {
        var options = OpenAIRequestOptions.withWebSearch()
        options.codeInterpreter = CodeInterpreterConfig(enabled: true)

        XCTAssertNotNil(options.webSearch)
        XCTAssertNotNil(options.codeInterpreter)
        XCTAssertTrue(options.webSearch?.enabled ?? false)
        XCTAssertTrue(options.codeInterpreter?.enabled ?? false)
    }

    func testCombiningOptions_AllToolsEnabled() {
        var options = OpenAIRequestOptions()
        options.webSearch = WebSearchConfig(enabled: true)
        options.fileSearch = FileSearchConfig(vectorStoreIds: ["vs_123"], enabled: true)
        options.codeInterpreter = CodeInterpreterConfig(enabled: true)
        options.reasoning = ReasoningConfig(effort: .high)

        XCTAssertTrue(options.webSearch?.enabled ?? false)
        XCTAssertTrue(options.fileSearch?.enabled ?? false)
        XCTAssertTrue(options.codeInterpreter?.enabled ?? false)
        XCTAssertNotNil(options.reasoning)
    }

    // MARK: - Service Tier Tests

    func testServiceTier_Default() {
        let options = OpenAIRequestOptions()
        XCTAssertNil(options.serviceTier)
    }

    func testServiceTier_Flex() {
        var options = OpenAIRequestOptions()
        options.serviceTier = .flex

        XCTAssertEqual(options.serviceTier, .flex)
    }

    func testServiceTier_Auto() {
        var options = OpenAIRequestOptions()
        options.serviceTier = .auto

        XCTAssertEqual(options.serviceTier, .auto)
    }

    // MARK: - Store and Background Tests

    func testStore_DefaultNil() {
        let options = OpenAIRequestOptions()
        XCTAssertNil(options.store)
    }

    func testStore_Enabled() {
        var options = OpenAIRequestOptions()
        options.store = true

        XCTAssertEqual(options.store, true)
    }

    func testBackground_DefaultNil() {
        let options = OpenAIRequestOptions()
        XCTAssertNil(options.background)
    }

    func testBackground_Enabled() {
        var options = OpenAIRequestOptions()
        options.background = true

        XCTAssertEqual(options.background, true)
    }

    // MARK: - Config Struct Tests

    func testWebSearchConfig_DomainFilters() {
        let config = WebSearchConfig(
            enabled: true,
            searchContextSize: .medium,
            domainFilters: DomainFilters(
                allowedDomains: ["example.com", "trusted.org"],
                blockedDomains: ["spam.com"]
            )
        )

        XCTAssertEqual(config.domainFilters?.allowedDomains?.count, 2)
        XCTAssertEqual(config.domainFilters?.blockedDomains?.count, 1)
    }

    func testFileSearchConfig_RankingOptions() {
        let config = FileSearchConfig(
            vectorStoreIds: ["vs_123"],
            enabled: true,
            rankingOptions: FileSearchRankingOptions(ranker: "default_2024_11_15", scoreThreshold: 0.5)
        )

        XCTAssertEqual(config.rankingOptions?.ranker, "default_2024_11_15")
        XCTAssertEqual(config.rankingOptions?.scoreThreshold, 0.5)
    }

    func testCodeInterpreterConfig_FileIds() {
        let config = CodeInterpreterConfig(
            enabled: true,
            containerId: "cntr_123",
            fileIds: ["file_abc", "file_def"]
        )

        XCTAssertEqual(config.fileIds?.count, 2)
        XCTAssertTrue(config.fileIds?.contains("file_abc") ?? false)
    }

    // MARK: - Encoding Tests

    func testServiceTier_Encoding() throws {
        let tiers: [ServiceTier] = [.auto, .default, .flex]
        let expected = ["auto", "default", "flex"]

        for (tier, expectedValue) in zip(tiers, expected) {
            XCTAssertEqual(tier.rawValue, expectedValue)
        }
    }

    func testSearchContextSize_Encoding() throws {
        let sizes: [SearchContextSize] = [.low, .medium, .high]
        let expected = ["low", "medium", "high"]

        for (size, expectedValue) in zip(sizes, expected) {
            XCTAssertEqual(size.rawValue, expectedValue)
        }
    }

    func testReasoningEffort_Encoding() throws {
        let efforts: [ReasoningConfig.ReasoningEffort] = [.low, .medium, .high]
        let expected = ["low", "medium", "high"]

        for (effort, expectedValue) in zip(efforts, expected) {
            XCTAssertEqual(effort.rawValue, expectedValue)
        }
    }

    func testReasoningSummary_Encoding() throws {
        let summaries: [ReasoningConfig.ReasoningSummary] = [.auto, .concise, .detailed]
        let expected = ["auto", "concise", "detailed"]

        for (summary, expectedValue) in zip(summaries, expected) {
            XCTAssertEqual(summary.rawValue, expectedValue)
        }
    }

    // MARK: - Domain Filter Convenience Tests

    func testDomainFilters_Allow() {
        let filters = DomainFilters.allow(["example.com", "trusted.org"])

        XCTAssertEqual(filters.allowedDomains, ["example.com", "trusted.org"])
        XCTAssertNil(filters.blockedDomains)
    }

    func testDomainFilters_Block() {
        let filters = DomainFilters.block(["spam.com", "malware.net"])

        XCTAssertNil(filters.allowedDomains)
        XCTAssertEqual(filters.blockedDomains, ["spam.com", "malware.net"])
    }

    // MARK: - User Location Tests

    func testUserLocation_Full() {
        let location = UserLocation(
            country: "US",
            region: "CA",
            city: "San Francisco",
            timezone: "America/Los_Angeles"
        )

        XCTAssertEqual(location.type, "approximate")
        XCTAssertEqual(location.country, "US")
        XCTAssertEqual(location.region, "CA")
        XCTAssertEqual(location.city, "San Francisco")
        XCTAssertEqual(location.timezone, "America/Los_Angeles")
    }

    func testUserLocation_CountryOnly() {
        let location = UserLocation(country: "UK")

        XCTAssertEqual(location.type, "approximate")
        XCTAssertEqual(location.country, "UK")
        XCTAssertNil(location.region)
        XCTAssertNil(location.city)
    }
}
