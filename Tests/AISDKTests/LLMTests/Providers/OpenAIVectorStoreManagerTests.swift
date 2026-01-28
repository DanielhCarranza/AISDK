//
//  OpenAIVectorStoreManagerTests.swift
//  AISDKTests
//
//  Tests for OpenAI Vector Store Manager functionality
//

import XCTest
@testable import AISDK

final class OpenAIVectorStoreManagerTests: XCTestCase {

    // MARK: - VectorStore Model Tests

    func testVectorStore_Decoding() throws {
        let json = """
        {
            "id": "vs_abc123",
            "object": "vector_store",
            "created_at": 1699000000,
            "name": "My Vector Store",
            "usage_bytes": 1024000,
            "file_counts": {
                "in_progress": 0,
                "completed": 5,
                "failed": 0,
                "cancelled": 0,
                "total": 5
            },
            "status": "completed",
            "expires_after": {
                "anchor": "last_active_at",
                "days": 30
            },
            "last_active_at": 1699500000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let store = try decoder.decode(VectorStore.self, from: json)

        XCTAssertEqual(store.id, "vs_abc123")
        XCTAssertEqual(store.object, "vector_store")
        XCTAssertEqual(store.name, "My Vector Store")
        XCTAssertEqual(store.usageBytes, 1024000)
        XCTAssertEqual(store.fileCounts.completed, 5)
        XCTAssertEqual(store.fileCounts.total, 5)
        XCTAssertEqual(store.status, .completed)
        XCTAssertNotNil(store.expiresAfter)
        XCTAssertEqual(store.expiresAfter?.days, 30)
    }

    func testVectorStore_WithOptionalFields() throws {
        let json = """
        {
            "id": "vs_xyz789",
            "object": "vector_store",
            "created_at": 1699000000,
            "usage_bytes": 0,
            "file_counts": {
                "in_progress": 1,
                "completed": 0,
                "failed": 0,
                "cancelled": 0,
                "total": 1
            },
            "status": "in_progress"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let store = try decoder.decode(VectorStore.self, from: json)

        XCTAssertNil(store.name)
        XCTAssertNil(store.expiresAfter)
        XCTAssertNil(store.expiresAt)
        XCTAssertNil(store.lastActiveAt)
        XCTAssertNil(store.metadata)
    }

    // MARK: - VectorStoreList Tests

    func testVectorStoreList_Decoding() throws {
        let json = """
        {
            "object": "list",
            "data": [
                {
                    "id": "vs_1",
                    "object": "vector_store",
                    "created_at": 1699000000,
                    "usage_bytes": 100,
                    "file_counts": {
                        "in_progress": 0,
                        "completed": 1,
                        "failed": 0,
                        "cancelled": 0,
                        "total": 1
                    },
                    "status": "completed"
                }
            ],
            "has_more": false,
            "first_id": "vs_1",
            "last_id": "vs_1"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let list = try decoder.decode(VectorStoreList.self, from: json)

        XCTAssertEqual(list.object, "list")
        XCTAssertEqual(list.data.count, 1)
        XCTAssertFalse(list.hasMore)
        XCTAssertEqual(list.firstId, "vs_1")
        XCTAssertEqual(list.lastId, "vs_1")
    }

    // MARK: - VectorStoreExpiration Tests

    func testVectorStoreExpiration_Creation() {
        let expiration = VectorStoreExpiration(days: 7)

        XCTAssertEqual(expiration.anchor, "last_active_at")
        XCTAssertEqual(expiration.days, 7)
    }

    func testVectorStoreExpiration_CustomAnchor() {
        let expiration = VectorStoreExpiration(anchor: "created_at", days: 14)

        XCTAssertEqual(expiration.anchor, "created_at")
        XCTAssertEqual(expiration.days, 14)
    }

    func testVectorStoreExpiration_AfterInactivity() {
        let expiration = VectorStoreExpiration.afterInactivity(days: 30)

        XCTAssertEqual(expiration.anchor, "last_active_at")
        XCTAssertEqual(expiration.days, 30)
    }

    // MARK: - ChunkingStrategy Tests

    func testChunkingStrategy_Auto() throws {
        let strategy = ChunkingStrategy.auto

        let encoder = JSONEncoder()
        let data = try encoder.encode(strategy)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "auto")
    }

    func testChunkingStrategy_Static() throws {
        let strategy = ChunkingStrategy.static(
            maxChunkSizeTokens: 1000,
            chunkOverlapTokens: 200
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(strategy)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "static")

        if let staticConfig = json["static"] as? [String: Any] {
            XCTAssertEqual(staticConfig["max_chunk_size_tokens"] as? Int, 1000)
            XCTAssertEqual(staticConfig["chunk_overlap_tokens"] as? Int, 200)
        } else {
            XCTFail("Expected static config")
        }
    }

    // MARK: - VectorStoreQuery Tests

    func testVectorStoreQuery_Text() {
        let query = VectorStoreQuery.text("search term")

        switch query {
        case .text(let text):
            XCTAssertEqual(text, "search term")
        case .vector:
            XCTFail("Expected text query")
        }
    }

    func testVectorStoreQuery_Vector() {
        let embedding: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let query = VectorStoreQuery.vector(embedding)

        switch query {
        case .text:
            XCTFail("Expected vector query")
        case .vector(let vec):
            XCTAssertEqual(vec.count, 5)
            XCTAssertEqual(vec[0], 0.1, accuracy: 0.001)
        }
    }

    // MARK: - VectorStoreFilters Tests

    func testVectorStoreFilters_And() throws {
        let filters = VectorStoreFilters.and([
            VectorStoreFilters.Filter(type: "eq", key: "category", value: "documents")
        ])

        XCTAssertEqual(filters.type, "and")
        XCTAssertEqual(filters.filters.count, 1)
        XCTAssertEqual(filters.filters[0].key, "category")
    }

    func testVectorStoreFilters_Or() throws {
        let filters = VectorStoreFilters.or([
            VectorStoreFilters.Filter(type: "eq", key: "type", value: "pdf"),
            VectorStoreFilters.Filter(type: "eq", key: "type", value: "docx")
        ])

        XCTAssertEqual(filters.type, "or")
        XCTAssertEqual(filters.filters.count, 2)
    }

    // MARK: - RankingOptions Tests

    func testRankingOptions_DefaultRanker() {
        let options = RankingOptions(scoreThreshold: 0.5)

        XCTAssertEqual(options.ranker, "default_2024_11_15")
        XCTAssertEqual(options.scoreThreshold, 0.5)
    }

    func testRankingOptions_CustomRanker() {
        let options = RankingOptions(ranker: "custom-ranker", scoreThreshold: 0.7)

        XCTAssertEqual(options.ranker, "custom-ranker")
        XCTAssertEqual(options.scoreThreshold, 0.7)
    }

    func testRankingOptions_Encoding() throws {
        let options = RankingOptions(scoreThreshold: 0.6)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(options)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["ranker"] as? String, "default_2024_11_15")
        XCTAssertEqual(json["score_threshold"] as? Double, 0.6)
    }

    // MARK: - VectorStoreSearchResults Tests

    func testVectorStoreSearchResults_Decoding() throws {
        let json = """
        {
            "object": "list",
            "search_query": "test query",
            "data": [
                {
                    "file_id": "file-abc123",
                    "filename": "document.pdf",
                    "score": 0.95,
                    "content": [
                        {
                            "type": "text",
                            "text": "This is the relevant content"
                        }
                    ],
                    "attributes": {}
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let results = try decoder.decode(VectorStoreSearchResults.self, from: json)

        XCTAssertEqual(results.object, "list")
        XCTAssertEqual(results.searchQuery, "test query")
        XCTAssertEqual(results.data.count, 1)

        let firstResult = results.data[0]
        XCTAssertEqual(firstResult.fileId, "file-abc123")
        XCTAssertEqual(firstResult.filename, "document.pdf")
        XCTAssertEqual(firstResult.score, 0.95, accuracy: 0.001)
    }

    // MARK: - VectorStoreFile Tests

    func testVectorStoreFile_Decoding() throws {
        let json = """
        {
            "id": "vsfile_abc123",
            "object": "vector_store.file",
            "created_at": 1699000000,
            "usage_bytes": 5000,
            "vector_store_id": "vs_parent",
            "status": "completed",
            "chunking_strategy": {
                "type": "auto"
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(VectorStoreFile.self, from: json)

        XCTAssertEqual(file.id, "vsfile_abc123")
        XCTAssertEqual(file.object, "vector_store.file")
        XCTAssertEqual(file.usageBytes, 5000)
        XCTAssertEqual(file.vectorStoreId, "vs_parent")
        XCTAssertEqual(file.status, .completed)
    }

    func testVectorStoreFile_WithLastError() throws {
        let json = """
        {
            "id": "vsfile_failed",
            "object": "vector_store.file",
            "created_at": 1699000000,
            "usage_bytes": 0,
            "vector_store_id": "vs_parent",
            "status": "failed",
            "last_error": {
                "code": "file_not_found",
                "message": "The specified file could not be found"
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(VectorStoreFile.self, from: json)

        XCTAssertEqual(file.status, .failed)
        XCTAssertNotNil(file.lastError)
        XCTAssertEqual(file.lastError?.code, "file_not_found")
    }

    // MARK: - VectorStoreFileList Tests

    func testVectorStoreFileList_Decoding() throws {
        let json = """
        {
            "object": "list",
            "data": [],
            "has_more": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let list = try decoder.decode(VectorStoreFileList.self, from: json)

        XCTAssertEqual(list.object, "list")
        XCTAssertEqual(list.data.count, 0)
        XCTAssertFalse(list.hasMore)
    }

    // MARK: - VectorStoreFileBatch Tests

    func testVectorStoreFileBatch_Decoding() throws {
        let json = """
        {
            "id": "vsfb_abc123",
            "object": "vector_store.file_batch",
            "created_at": 1699000000,
            "vector_store_id": "vs_parent",
            "status": "in_progress",
            "file_counts": {
                "in_progress": 3,
                "completed": 2,
                "failed": 0,
                "cancelled": 0,
                "total": 5
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let batch = try decoder.decode(VectorStoreFileBatch.self, from: json)

        XCTAssertEqual(batch.id, "vsfb_abc123")
        XCTAssertEqual(batch.object, "vector_store.file_batch")
        XCTAssertEqual(batch.vectorStoreId, "vs_parent")
        XCTAssertEqual(batch.status, .inProgress)
        XCTAssertEqual(batch.fileCounts.inProgress, 3)
        XCTAssertEqual(batch.fileCounts.completed, 2)
        XCTAssertEqual(batch.fileCounts.total, 5)
    }

    // MARK: - FileCounts Tests

    func testFileCounts_Decoding() throws {
        let json = """
        {
            "in_progress": 1,
            "completed": 10,
            "failed": 2,
            "cancelled": 1,
            "total": 14
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let counts = try decoder.decode(VectorStore.FileCounts.self, from: json)

        XCTAssertEqual(counts.inProgress, 1)
        XCTAssertEqual(counts.completed, 10)
        XCTAssertEqual(counts.failed, 2)
        XCTAssertEqual(counts.cancelled, 1)
        XCTAssertEqual(counts.total, 14)
    }

    // MARK: - LastError Tests

    func testLastError_Decoding() throws {
        let json = """
        {
            "code": "invalid_request",
            "message": "The request was invalid"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let error = try decoder.decode(VectorStoreFile.LastError.self, from: json)

        XCTAssertEqual(error.code, "invalid_request")
        XCTAssertEqual(error.message, "The request was invalid")
    }

    // MARK: - Integration Pattern Tests

    func testVectorStore_WorkflowPattern() {
        // This test demonstrates the expected workflow pattern

        // 1. Create a vector store
        let createExpiration = VectorStoreExpiration(days: 30)
        XCTAssertEqual(createExpiration.anchor, "last_active_at")

        // 2. Use auto chunking for files
        let chunkingStrategy = ChunkingStrategy.auto
        if case .auto = chunkingStrategy {
            // Expected
        } else {
            XCTFail("Expected auto chunking")
        }

        // 3. Configure search with ranking
        let rankingOptions = RankingOptions(scoreThreshold: 0.5)
        XCTAssertNotNil(rankingOptions.scoreThreshold)
        XCTAssertEqual(rankingOptions.scoreThreshold, 0.5)

        // 4. Create text query
        let query = VectorStoreQuery.text("search term")
        if case .text(let text) = query {
            XCTAssertFalse(text.isEmpty)
        } else {
            XCTFail("Expected text query")
        }
    }
}
