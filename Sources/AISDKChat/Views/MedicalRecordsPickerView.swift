import SwiftUI

struct MedicalRecordsPickerView: View {
    @Environment(HealthProfile.self) private var healthProfile
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedCategory: MedicalRecordType = .biomarker
    @State private var selectedRecords: [MedicalRecord] = []
    @FocusState private var isSearchFocused: Bool
    
    // Using mock data for now
    @State private var allRecords: [MedicalRecord] = MedicalRecord.mockData()
    
    var onSelectionComplete: ([MedicalRecord]) -> Void
    
    var filteredRecords: [MedicalRecord] {
        allRecords.filter { record in
            (searchText.isEmpty || 
             record.name.localizedCaseInsensitiveContains(searchText) ||
             record.summary.localizedCaseInsensitiveContains(searchText)) &&
            record.recordType == selectedCategory
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                
                // Category tabs
                categoryTabs
                
                // Records list
                recordsList
            }
            .navigationTitle("Select Medical Records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedRecords.count)") {
                        onSelectionComplete(selectedRecords)
                        dismiss()
                    }
                    .disabled(selectedRecords.isEmpty)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            isSearchFocused = false
                        }
                    }
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray6))
                    .frame(height: 40)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .padding(.leading, 10)
                    
                    TextField("Search medical records", text: $searchText)
                        .focused($isSearchFocused)
                        .padding(.vertical, 8)
                        .padding(.leading, 2)
                        .padding(.trailing, 8)
                        .autocorrectionDisabled()
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            isSearchFocused = true
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .padding(.trailing, 8)
                        }
                    }
                }
            }
        }
        .padding()
    }
    
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(MedicalRecordType.allCases, id: \.self) { category in
                    VStack(spacing: 8) {
                        Image(systemName: category.icon)
                            .font(.title3)
                        
                        Text(category.displayName)
                            .font(.caption)
                    }
                    .foregroundColor(selectedCategory == category ? .accentColor : .primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedCategory == category ? 
                                  Color.accentColor.opacity(0.1) : Color.clear)
                    )
                    .onTapGesture {
                        selectedCategory = category
                        // Dismiss keyboard when changing categories
                        isSearchFocused = false
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }
    
    private var recordsList: some View {
        List {
            if filteredRecords.isEmpty {
                emptyStateView
            } else {
                ForEach(filteredRecords) { record in
                    recordRow(record)
                }
            }
        }
        .listStyle(PlainListStyle())
        .animation(.default, value: filteredRecords.count)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            if !searchText.isEmpty {
                Text("No records match '\(searchText)'")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Button("Clear Search") {
                    searchText = ""
                }
                .buttonStyle(.bordered)
            } else {
                Text("No \(selectedCategory.displayName.lowercased()) available")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .padding()
    }
    
    private func recordRow(_ record: MedicalRecord) -> some View {
        let isSelected = selectedRecords.contains { $0.id == record.id }
        
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.name)
                    .font(.headline)
                
                Text(record.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(record.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
                    .font(.title3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedRecords.removeAll { $0.id == record.id }
            } else {
                selectedRecords.append(record)
            }
            
            // Add haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    MedicalRecordsPickerView { records in
        print("Selected \(records.count) records")
    }
    .environment(HealthProfile())
} 