//
//  MetadataView.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 14/03/25.
//

import Foundation
import SwiftUI


struct MetadataView: View {
    let metadata: ToolMetadata
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let evidence = metadata as? MedicalEvidence {
                        medicalEvidenceView(evidence)
                    } else if let sources = metadata as? Sources {
                        sourcesView(sources)
                    } else if let source = metadata as? Source {
                        sourceView(source)
                    }
                }
                .padding()
            }
            .navigationTitle("Sources & Evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func medicalEvidenceView(_ evidence: MedicalEvidence) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Evidence Level: ")
                    .fontWeight(.medium)
                Text(evidence.evidenceLevel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue.opacity(0.2))
                    )
            }
            
            if let score = evidence.confidenceScore {
                HStack {
                    Text("Confidence Score: ")
                        .fontWeight(.medium)
                    Text("\(Int(score * 100))%")
                }
            }
            
            Text("Sources:")
                .fontWeight(.medium)
            
            ForEach(evidence.sources, id: \.url) { source in
                sourceView(source)
                    .padding(.leading)
            }
            
            Text("Last Updated: \(evidence.lastUpdated.formatted())")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    private func sourcesView(_ sources: Sources) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header section
            VStack(alignment: .leading, spacing: 8) {
                Text("Medical Evidence Search Results")
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                    
                    Text("Found \(sources.results.count) relevant sources")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 8)
            
            // Results count indicator
            if !sources.results.isEmpty {
                HStack {
                    Rectangle()
                        .frame(width: 4, height: 20)
                        .foregroundColor(.blue)
                    
                    Text("\(sources.results.count) \(sources.results.count == 1 ? "Source" : "Sources")")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            // Sources list
            ForEach(sources.results.indices, id: \.self) { index in
                sourceCardView(sources.results[index], index: index + 1)
            }
            
            // Empty state
            if sources.results.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    
                    Text("No sources found")
                        .font(.headline)
                    
                    Text("Try refining your search query or check back later")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }
    
    private func sourceCardView(_ source: Source, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Source number and evidence type
            HStack {
                Text("#\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                
                Spacer()
                
                Text(source.evidenceType)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(evidenceTypeColor(source.evidenceType).opacity(0.1))
                    )
                    .foregroundColor(evidenceTypeColor(source.evidenceType))
            }
            
            // Title
            Link(destination: URL(string: source.url) ?? URL(string: "https://example.com")!) {
                Text(source.title)
                    .font(.headline)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.leading)
            }
            
            // Content preview
            Text(source.content ?? " ")
                .font(.body)
                .lineLimit(3)
                .foregroundColor(.primary)
            
            // URL preview
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                Text(source.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
    
    private func evidenceTypeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "clinical trial", "randomized controlled trial", "rct":
            return .green
        case "meta-analysis", "systematic review":
            return .blue
        case "observational study", "cohort study", "case-control":
            return .orange
        case "expert opinion", "consensus":
            return .purple
        case "error":
            return .red
        default:
            return .gray
        }
    }
    
    private func sourceView(_ source: Source) -> some View {
        sourceCardView(source, index: 1)
    }
}

// Add a new view for displaying medical record details
struct MedicalRecordDetailView: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let recordData = attachment.medicalRecordData,
                       let record = try? JSONDecoder().decode(MedicalRecord.self, from: recordData) {
                        
                        // Header with record type and date
                        HStack {
                            Image(systemName: record.recordType.icon)
                                .font(.title)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text(record.recordType.displayName)
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text(record.date, style: .date)
                                    .font(.subheadline)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        
                        // Record name and summary
                        VStack(alignment: .leading, spacing: 8) {
                            Text(record.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(record.summary)
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top)
                        
                        // Divider
                        Divider()
                            .padding(.vertical)
                        
                        // Details
                        Text("Details")
                            .font(.headline)
                        
                        Text(record.details)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    } else {
                        Text("Unable to load medical record details")
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
            .navigationTitle(attachment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
