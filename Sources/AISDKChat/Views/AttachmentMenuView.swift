import SwiftUI

struct AttachmentMenuView: View {
    @Environment(\.dismiss) private var dismiss
    
    var onCameraSelected: () -> Void
    var onPhotosSelected: () -> Void
    var onFilesSelected: () -> Void
    var onMedicalRecordsSelected: () -> Void = {}
    
    var body: some View {
        ZStack {
            // Base blur background
            Color.black.opacity(0.2)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
            
            // Content
            VStack(spacing: 20) {
                Spacer()
                
                VStack(spacing: 15) {
                    AttachmentButton(
                        icon: "heart.text.square",
                        title: "Medical Records",
                        action: {
                            onMedicalRecordsSelected()
                            dismiss()
                        }
                    )
                    
                    AttachmentButton(
                        icon: "camera",
                        title: "Camera",
                        action: {
                            onCameraSelected()
                            dismiss()
                        }
                    )
                    
                    AttachmentButton(
                        icon: "photo",
                        title: "Photos",
                        action: {
                            onPhotosSelected()
                            dismiss()
                        }
                    )
                    
                    AttachmentButton(
                        icon: "folder",
                        title: "Files",
                        action: {
                            onFilesSelected()
                            dismiss()
                        }
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
    }
}

struct AttachmentButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
                
                Text(title)
                    .font(.system(size: 17))
                
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            // .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
}

#Preview {
    AttachmentMenuView(
        onCameraSelected: {},
        onPhotosSelected: {},
        onFilesSelected: {},
        onMedicalRecordsSelected: {}
    )
} 