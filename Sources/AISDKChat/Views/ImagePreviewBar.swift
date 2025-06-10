import SwiftUI

struct ImagePreviewBar: View {
    let images: [ImageData]
    @Binding var isUploading: Bool
    var onRemove: (Int) -> Void
    
    struct ImageData: Identifiable {
        let id = UUID()
        let data: Data
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    if let uiImage = UIImage(data: image.data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                if isUploading {
                                    ProgressView()
                                        .padding(4)
                                        .background(.thinMaterial)
                                        .clipShape(Circle())
                                } else {
                                    Button(action: { onRemove(index) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                            .background(.thinMaterial)
                                            .clipShape(Circle())
                                    }
                                }
                            }
                            .offset(x: 6, y: -6)
                    }
                }
                
                if !images.isEmpty {
                    Text("\(images.count)/4")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: images.isEmpty ? 0 : 50)
    }
} 