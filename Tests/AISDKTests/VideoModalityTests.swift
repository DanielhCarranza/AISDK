//
//  VideoModalityTests.swift
//  AISDKTests
//
//  Tests for video modality support in AIMessage and AIInputMessage
//

import XCTest
@testable import AISDK

final class VideoModalityTests: XCTestCase {
    func testContentPartVideoCodableRoundTrip() throws {
        let videoData = Data([0x01, 0x02, 0x03])
        let original = AIMessage.ContentPart.video(videoData, mimeType: "video/mp4")

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIMessage.ContentPart.self, from: encoded)

        switch decoded {
        case .video(let data, let mimeType):
            XCTAssertEqual(data, videoData)
            XCTAssertEqual(mimeType, "video/mp4")
        default:
            XCTFail("Expected video content part")
        }
    }

    func testContentPartVideoURLCodableRoundTrip() throws {
        let urlString = "https://example.com/video.mp4"
        let original = AIMessage.ContentPart.videoURL(urlString)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIMessage.ContentPart.self, from: encoded)

        switch decoded {
        case .videoURL(let url):
            XCTAssertEqual(url, urlString)
        default:
            XCTFail("Expected videoURL content part")
        }
    }

    func testAIMessageVideoPartsCodable() throws {
        let videoData = Data("sample video".utf8)
        let message = AIMessage(
            role: .user,
            content: .parts([
                .text("Describe this clip"),
                .video(videoData, mimeType: "video/mp4")
            ])
        )

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(AIMessage.self, from: encoded)

        switch decoded.content {
        case .parts(let parts):
            XCTAssertEqual(parts.count, 2)
            guard case .text(let text) = parts[0] else {
                return XCTFail("Expected text content part")
            }
            XCTAssertEqual(text, "Describe this clip")
            guard case .video(let data, let mimeType) = parts[1] else {
                return XCTFail("Expected video content part")
            }
            XCTAssertEqual(data, videoData)
            XCTAssertEqual(mimeType, "video/mp4")
        default:
            XCTFail("Expected parts content")
        }
    }

    func testAIInputMessageHasVideo() {
        let videoData = Data([0x09, 0x0A])
        let withVideo = AIInputMessage.user([
            .text("Check this"),
            .video(videoData, format: .mp4)
        ])
        let withoutVideo = AIInputMessage.user([.text("No video here")])

        XCTAssertTrue(withVideo.hasVideo)
        XCTAssertFalse(withoutVideo.hasVideo)
    }

    func testAIInputMessageVideos() {
        let videoData = Data([0x0B, 0x0C])
        let videoURL = URL(string: "https://example.com/clip.mov")!
        let message = AIInputMessage.user([
            .video(videoData, format: .mp4),
            .videoURL(videoURL, format: .mov)
        ])

        let videos = message.videos
        XCTAssertEqual(videos.count, 2)
        XCTAssertTrue(videos.contains { $0.data == videoData })
        XCTAssertTrue(videos.contains { $0.url == videoURL })
    }

    func testMixedMultimodalFlags() {
        let imageData = Data("image".utf8)
        let videoData = Data("video".utf8)
        let message = AIInputMessage.user([
            .text("Describe the image and video"),
            .image(imageData, detail: .auto),
            .video(videoData, format: .mp4)
        ])

        XCTAssertTrue(message.hasImages)
        XCTAssertTrue(message.hasVideo)
        XCTAssertEqual(message.images.count, 1)
        XCTAssertEqual(message.videos.count, 1)
    }
}
