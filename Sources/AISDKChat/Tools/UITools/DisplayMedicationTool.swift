import SwiftUI

/// Tool for displaying medications in a chat interface
struct DisplayMedicationTool: RenderableTool {
    let name = "display_medications"
    let description = "Display current list of medications in a visual format"
    
    @Parameter(description: "Medications to display")
    var query: String = ""

    private let viewModel = MedicationsViewModel()
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        do {
            // First try to get medications
            let medications = try await viewModel.getMedications()
            
            // Create text response
            let textResponse: String
            if medications.isEmpty {
                textResponse = "You don't have any medications added yet."
                // Return early if empty to avoid encoding
                return (textResponse, nil)
            } else {
                textResponse = "You have \(medications.count) medication(s):\n" +
                    medications.map { "• \($0.name) - \($0.dosageDescription)" }.joined(separator: "\n")
            }
            
            // Try encoding medications with specific error handling
            do {
                let jsonData = try JSONEncoder().encode(medications)
                let metadata = RenderMetadata(toolName: name, jsonData: jsonData)
                return (textResponse, metadata)
            } catch {
                print("⚠️ JSON Encoding error: \(error)")
                // If encoding fails, return just the text response
                return (textResponse + "\n\nNote: Unable to display visual medication list.", nil)
            }
        } catch {
            print("⚠️ Database fetch error: \(error)")
            throw error
        }
    }
    
    func render(from data: Data) -> AnyView {
        let medications = (try? JSONDecoder().decode([Medication].self, from: data)) ?? []
        
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Medications")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                if medications.isEmpty {
                    Text("No medications added yet")
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(medications, id: \.self) { medication in
                                MedicationCardView(medication: medication)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
            .padding()
            .cornerRadius(12)
        )
    }
}

/// Simplified version of MedicationRow for chat interface
private struct MedicationCardView: View {
    let medication: Medication
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(medication.name)
                        .font(.headline)
                    Text(medication.dosageDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let nextDose = medication.nextDoseTime {
                    Text(nextDose)
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
            }
            
            HStack {
                Label {
                    Text(medication.frequencyDescription)
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
} 
