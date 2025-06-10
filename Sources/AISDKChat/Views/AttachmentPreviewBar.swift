import SwiftUI
import PDFKit

struct AttachmentPreviewBar: View {
    struct PreviewItem: Identifiable {
        enum PreviewType {
            case image(Data)
            case file(URL, String, AttachmentType)
            case medicalRecord(MedicalRecord)
            case uploading(String, AttachmentType)
        }
        
        let id = UUID()
        let type: PreviewType
        var isUploading: Bool = false
    }
    
    var items: [PreviewItem]
    var onRemove: (Int) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ZStack(alignment: .topTrailing) {
                        // Content container
                        ZStack {
                            switch item.type {
                            case .image(let data):
                                if let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                }
                            case .file(_, let filename, let type):
                                filePreview(filename: filename, type: type)
                            case .medicalRecord(let record):
                                medicalRecordPreview(record: record)
                            case .uploading(let filename, let type):
                                filePreview(filename: filename, type: type)
                                    .overlay(
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                    )
                            }
                            
                            if item.isUploading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(8)
                            }
                        }
                        .frame(width: 60, height: 60)
                        
                        // Remove button - now positioned at top right
                        Button {
                            // Call the onRemove closure with the current index
                            onRemove(index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(BorderlessButtonStyle()) // Prevent tap gesture conflicts
                        .padding(-5) // Adjust position to be slightly outside the frame
                        .zIndex(1) // Ensure button is above the content
                    }
                    .padding(.top, 8) // Add some padding at the top to accommodate the button
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 80)
    }
    
    private func filePreview(filename: String, type: AttachmentType) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 60, height: 60)
            
            VStack {
                Image(systemName: type.icon)
                    .font(.system(size: 24))
                
                Text(filename.prefix(10))
                    .font(.system(size: 8))
                    .lineLimit(1)
            }
        }
    }
    
    private func medicalRecordPreview(record: MedicalRecord) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.1))
                .frame(width: 60, height: 60)
            
            VStack(spacing: 4) {
                Image(systemName: record.recordType.icon)
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                
                Text(record.name)
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                
                Text(record.summary)
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(4)
        }
    }
}

// // For previews
// struct ImagePreviewBar {
//     struct ImageData: Identifiable {
//         let id = UUID()
//         let data: Data
//     }
// }

// #Preview {
//     let mockRecord = MedicalRecord.mockData().first!
    
//     return AttachmentPreviewBar(
//         items: [
//             AttachmentPreviewBar.PreviewItem(
//                 type: .file(URL(string: "file://test.pdf")!, "Document.pdf", .pdf)
//             ),
//             AttachmentPreviewBar.PreviewItem(
//                 type: .medicalRecord(mockRecord)
//             )
//         ],
//         onRemove: { _ in }
//     )
//}
