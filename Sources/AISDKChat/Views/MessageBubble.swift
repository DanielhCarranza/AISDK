//
//  MessageBubble.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 05/01/25.
//

import MarkdownUI
import SwiftUI

struct MessageBubble: View {
    let chatMessage: ChatMessage
    @State private var showingMetadata = false
    @State private var selectedAttachment: Attachment?
    
    var body: some View {
        // Return EmptyView if the message is hidden
        if chatMessage.hidden {
            EmptyView()
        }
        else if !chatMessage.displayContent.isEmpty {
            HStack {
                switch chatMessage.message {
                case .user:
                    Spacer()
                    userMessageView
                case .assistant:
                    assistantMessageView
                    Spacer()
                case let .tool(content, toolName, _):
                    // Check if we have RenderMetadata
                    if let renderMeta = chatMessage.metadata as? RenderMetadata {
                        // Attempt to build a UI from the tool
                        if let toolType = AIToolRegistry.toolType(forName: toolName),
                           let renderable = toolType.init() as? RenderableTool {
                            toolView(for: renderable, data: renderMeta.jsonData)
                        } else {
                            EmptyView()
                        }
                    } else if let researchMeta = chatMessage.metadata as? ResearchMetadata {
                        // Render a simple view for ResearchMetadata
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .center, spacing: 12) {
                                // Display the tool icon with the metadata color
                                Image(systemName: researchMeta.icon)
                                    .font(.caption)
                                    .foregroundColor(researchMeta.color)
                                    .frame(width: 24, height: 24)
                                    .background(researchMeta.color.opacity(0.1))
                                    .clipShape(Circle())
                                
                                // Display the tool name if available
                                if let toolName = researchMeta.toolName {
                                    Text(toolName.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }
                                
                                Spacer()
                                
                                // Display source count if available
                                if researchMeta.sources.count > 0 {
                                    HStack(spacing: 4) {
                                        Text("\(researchMeta.sources.count) sources")
                                            .font(.caption2)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(researchMeta.color.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                            
                            // Display the content
                            Markdown(researchMeta.topic)
                                .font(.caption2)
                                .fontWeight(.ultraLight)
                                .lineLimit(3)
                                .padding(.leading, 12)
                                .background(Color(.systemBackground))
                        }
                    } else {
                        EmptyView()
                    }
                    Spacer()
                default:
                    EmptyView()
                }
            }
        }
    }
    
    private var userMessageView: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Display images from message parts
            if case .user(let content, _) = chatMessage.message,
               case .parts(let parts) = content {
                let imageParts = parts.compactMap { part -> URL? in
                    if case .imageURL(.url(let url), _) = part {
                        return url
                    }
                    return nil
                }
                
                // Display attachments
                if !chatMessage.attachments.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        // Display attachments
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 4) {
                            ForEach(chatMessage.attachments) { attachment in
                                switch attachment.type {
                                case .image:
                                    AsyncImage(url: attachment.url) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 150)
                                                .background(Color.gray.opacity(0.1))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 150)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        case .failure:
                                            Image(systemName: "photo.fill")
                                                .font(.largeTitle)
                                                .foregroundColor(.gray)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 150)
                                                .background(Color.gray.opacity(0.1))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                case .medicalRecord:
                                    Button(action: {
                                        selectedAttachment = attachment
                                    }) {
                                        HStack {
                                            Image(systemName: attachment.medicalRecordType?.icon ?? "heart.text.square")
                                                .font(.title2)
                                                .foregroundColor(.blue)
                                            
                                            VStack(alignment: .leading) {
                                                Text(attachment.name)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                
                                                Text(attachment.content ?? "")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .padding(8)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                default:
                                    Button(action: {
                                        if attachment.type == .pdf {
                                            selectedAttachment = attachment
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: attachment.type.icon)
                                                .font(.title2)
                                            
                                            VStack(alignment: .leading) {
                                                Text(attachment.name)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                
                                                Text(attachment.type.rawValue.uppercased())
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(8)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                }
            }
            
            // Display text content
            VStack(alignment: .trailing, spacing: 4) {
                Markdown(chatMessage.displayContent)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                
                if chatMessage.metadata != nil {
                    metadataButton
                }
            }
        }
        .sheet(item: $selectedAttachment) { attachment in
            if attachment.type == .pdf {
                PDFViewerSheet(url: attachment.url, title: attachment.name)
            } else if attachment.type == .medicalRecord {
                MedicalRecordDetailView(attachment: attachment)
            }
        }
    }
    
    private var assistantMessageView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .clipped()
                
                VStack(alignment: .leading, spacing: 8) {                    
                    if !chatMessage.displayContent.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Markdown(chatMessage.displayContent)
                                .padding()
                                .background(Color(red: 5 / 255, green: 7 / 255, blue: 14 / 255))
                                .foregroundColor(.white)
                                .cornerRadius(16)
                            
                            // Add debug print to verify metadata
                            if chatMessage.metadata != nil {
                                metadataButton
                                    .padding(.leading)  // Add some padding
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingMetadata) {
            if let metadata = chatMessage.metadata {
                MetadataView(metadata: metadata)
            }
        }
    }
    
    private func toolView(for renderable: RenderableTool, data: Data) -> some View {
        renderable.render(from: data)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
    }
    
    private func fallbackToolView(_ text: String) -> some View {
        VStack(alignment: .leading) {
            Markdown(text)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(16)
        }
    }
    
    private var metadataButton: some View {
        Button(action: { showingMetadata = true }) {
            Label("Sources", systemImage: "link")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .buttonStyle(.plain)
    }
}

