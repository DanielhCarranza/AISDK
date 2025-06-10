//
//  AIMessageInputView.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 05/01/25.
//

import SwiftUI
import AVFoundation
import Speech
import SpeziSpeechRecognizer
import PhotosUI

struct AIMessageInputView: View {
    // MARK: - Environment & State
    
    @Environment(AIChatManager.self) private var chat
    @Environment(HealthProfile.self) private var healthProfile
    
    // Local state for text input with debouncing
    @State private var localInputText = ""
    @State private var debouncedTask: Task<Void, Never>?
    
    // Other state properties
    @State private var showingAttachmentMenu = false
    @State private var speechRecognizer = SpeechRecognizer()
    @State private var showingVoiceMode = false
    @State private var selectedImages: [ImagePreviewBar.ImageData] = []
    @State private var imageSelection: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var scrollID: String?
    @State private var scrollInterrupted = false
    @FocusState var isInputFocused: Bool
    
    // Add state for handling file attachments
    @State private var selectedFiles: [URL] = []
    @State private var showingFilePicker = false
    
    // Add state for medical records
    @State private var showingMedicalRecordsPicker = false
    @State private var selectedMedicalRecords: [MedicalRecord] = []
    
    // MARK: - Input Area View
    private var inputArea: some View {
        HStack {
            // Attachment button
            if !chat.state.isProcessing {
                attachmentButton
            }
            
            // TextField in its own container
            textInputField
                .focused($isInputFocused)
                .disabled(chat.state.isProcessing)
                .frame(minHeight: 40)
                .overlay(alignment: .trailing) {
                    actionButton
                        .padding(.trailing, 8)
                }
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.2))
                }
            
            // Voice mode button
            if !chat.state.isProcessing {
                voiceModeButton
            }
        }
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 8) {
            // Image Preview
            if !selectedImages.isEmpty || !selectedFiles.isEmpty || !selectedMedicalRecords.isEmpty {
                AttachmentPreviewBar(
                    items: selectedImages.map { imageData in
                        AttachmentPreviewBar.PreviewItem(
                            type: .image(imageData.data)
                        )
                    } + selectedFiles.map { fileURL in
                        AttachmentPreviewBar.PreviewItem(
                            type: .file(
                                fileURL,
                                fileURL.lastPathComponent,
                                AttachmentType.from(fileExtension: fileURL.pathExtension)
                            )
                        )
                    } + selectedMedicalRecords.map { record in
                        AttachmentPreviewBar.PreviewItem(
                            type: .medicalRecord(record)
                        )
                    },
                    onRemove: { index in
                        removeAttachment(at: index)
                    }
                )
            }
            
            inputArea
        }
        .onChange(of: localInputText) { _, newValue in
            // Debounce text updates
            debouncedTask?.cancel()
            debouncedTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay
                if !Task.isCancelled {
                    // Update any dependent state here if needed
                }
            }
        }
        .sheet(isPresented: $showingAttachmentMenu) {
            AttachmentMenuView(
                onCameraSelected: {
                    showingAttachmentMenu = false
                    showingCamera = true
                },
                onPhotosSelected: {
                    showingAttachmentMenu = false
                    showingPhotoPicker = true
                },
                onFilesSelected: {
                    showingAttachmentMenu = false
                    showingFilePicker = true
                },
                onMedicalRecordsSelected: {
                    showingAttachmentMenu = false
                    showingMedicalRecordsPicker = true
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(.ultraThinMaterial)
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $imageSelection,
            maxSelectionCount: 4,
            matching: .images,
            preferredItemEncoding: .automatic
        )
        .onChange(of: imageSelection) { _ , newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            selectedImages.append(ImagePreviewBar.ImageData(data: data))
                        }
                    }
                }
                // Clear selection after processing
                await MainActor.run {
                    imageSelection = []
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView(image: Binding(
                get: { nil },
                set: { newImage in
                    if let image = newImage,
                       let imageData = image.jpegData(compressionQuality: 0.8) {
                        selectedImages.append(ImagePreviewBar.ImageData(data: imageData))
                    }
                }
            ), isShown: $showingCamera)
        }
        .navigationDestination(isPresented: $showingVoiceMode) {
            AIVoiceModeView()
                .environment(healthProfile)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    for url in urls {
                        do {
                            // Start accessing the security-scoped resource
                            guard url.startAccessingSecurityScopedResource() else {
                                print("❌ Failed to access security-scoped resource: \(url)")
                                continue
                            }
                            
                            // Create a local copy in the app's temporary directory
                            let tempDir = FileManager.default.temporaryDirectory
                            let localURL = tempDir.appendingPathComponent(url.lastPathComponent)
                            
                            // Copy the file to our temporary location
                            let data = try Data(contentsOf: url)
                            try data.write(to: localURL)
                            
                            // Stop accessing the original resource
                            url.stopAccessingSecurityScopedResource()
                            
                            // Add the local URL to our selected files
                            await MainActor.run {
                                if !selectedFiles.contains(localURL) {
                                    selectedFiles.append(localURL)
                                }
                            }
                        } catch {
                            print("❌ Failed to copy file: \(error)")
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                }
            case .failure(let error):
                print("❌ File import failed: \(error)")
            }
        }
        .sheet(isPresented: $showingMedicalRecordsPicker) {
            MedicalRecordsPickerView { records in
                selectedMedicalRecords = records
            }
            .environment(healthProfile)
        }
    }
    
    // MARK: - Subviews
    private var textInputField: some View {
        TextField("Ask a question...", text: $localInputText, axis: .vertical)
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }
    
    private var actionButton: some View {
        Group {
            if chat.state.isProcessing {
                stopButton
            } else if speechRecognizer.isAvailable && (localInputText.isEmpty || speechRecognizer.isRecording) {
                microphoneButton
            } else {
                sendButton
            }
        }
    }
    
    // MARK: - Action Buttons
    private var sendButton: some View {
        Button(action: sendMessage) {
            Group {
                if chat.isUploading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .accessibilityLabel("Send Message")
                        .font(.title2)
                }
            }
            .foregroundColor(sendButtonForegroundColor)
        }
        .disabled(localInputText.isEmpty && selectedImages.isEmpty && selectedFiles.isEmpty && selectedMedicalRecords.isEmpty || chat.state.isProcessing || chat.isUploading)
    }
    
    private var attachmentButton: some View {
        Button(action: {
            showingAttachmentMenu = true
        }) {
            Image(systemName: "plus.circle.fill")
                .accessibilityLabel("Add Attachment")
                .font(.title)
                .foregroundColor(.gray)
        }
        .offset(x: 0, y: -3)
    }
    
    private var microphoneButton: some View {
        Button(action: microphoneButtonPressed) {
            Image(systemName: "mic.fill")
                .accessibilityLabel("Microphone Button")
                .font(.title2)
                .foregroundColor(microphoneForegroundColor)
                .scaleEffect(speechRecognizer.isRecording ? 1.2 : 1.0)
                .opacity(speechRecognizer.isRecording ? 0.7 : 1.0)
                .animation(
                    speechRecognizer.isRecording ? 
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : 
                        .default,
                    value: speechRecognizer.isRecording
                )
        }
    }
    
    private var sendButtonForegroundColor: Color {
        (localInputText.isEmpty && selectedImages.isEmpty && selectedFiles.isEmpty && selectedMedicalRecords.isEmpty) ? Color(.systemGray5) : .accentColor
    }
    
    private var microphoneForegroundColor: Color {
        speechRecognizer.isRecording ? .red : Color(.systemGray2)
    }
    
    private var stopButton: some View {
        Button(action: {
            chat.stopStreaming()
        }) {
            Image(systemName: "stop.circle.fill")
                .accessibilityLabel("Stop Generation")
                .font(.title2)
                .foregroundColor(.red)
        }
    }
    
    private var voiceModeButton: some View {
        Button(action: {
            showingVoiceMode = true
        }) {
            ZStack {
                MeshGradientCircle()
                    .frame(width: 32, height: 32)
                
                Image(systemName: "waveform.and.mic")
                    .accessibilityLabel("Voice Mode")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
        }
        .offset(x: 0, y: -3)
    }
    
    // MARK: - Actions
    private func sendMessage() {
        let text = localInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !text.isEmpty || !selectedImages.isEmpty || !selectedFiles.isEmpty || !selectedMedicalRecords.isEmpty {
            print("📎 Sending message with \(selectedImages.count) images, \(selectedFiles.count) files, and \(selectedMedicalRecords.count) medical records")
            
            isInputFocused = false
            scrollInterrupted = false
            Task {
                await MainActor.run { chat.isUploading = true }
                
                var parts: [UserContent.Part] = []
                var messageAttachments: [Attachment] = []
                
                // Always add text part, even if empty
                parts.append(.text(text))
                
                // Upload and add images if any
                for imageData in selectedImages {
                    do {
                        let url = try await chat.uploadImage(imageData.data)
                        print("📷 Uploaded image to: \(url)")
                        
                        // Images are added both to the message parts (for LLM) and as attachments
                        parts.append(.imageURL(.url(url)))
                        
                        let attachment = Attachment(
                            url: url,
                            name: "Image",
                            type: .image
                        )
                        messageAttachments.append(attachment)
                    } catch {
                        print("❌ Failed to upload image: \(error)")
                    }
                }
                
                // Parse and upload files
                if !selectedFiles.isEmpty {
                    do {
                        let parsedAttachments = try await chat.parseAndUploadFiles(selectedFiles)
                        messageAttachments.append(contentsOf: parsedAttachments)
                        
                        // Add file content as text parts for context
                        for attachment in parsedAttachments where attachment.content != nil {
                            parts.append(.text("\n\nFile: \(attachment.name)\n\(attachment.content ?? "")"))
                        }
                    } catch {
                        print("❌ Failed to process files: \(error)")
                    }
                }
                
                // Add medical records
                for record in selectedMedicalRecords {
                    let attachment = Attachment(medicalRecord: record)
                    messageAttachments.append(attachment)
                    
                    // Add medical record content as text for context
                    parts.append(.text("\n\nMedical Record: \(record.name)\nDate: \(record.date.formatted(date: .long, time: .omitted))\nSummary: \(record.summary)"))
                }
                
                print("📤 Sending message with \(messageAttachments.count) attachments")
                
                await MainActor.run {
                    chat.sendMessage(parts, attachments: messageAttachments)
                    localInputText = ""
                    selectedImages = []
                    selectedFiles = []
                    selectedMedicalRecords = []
                    chat.isUploading = false
                    
                    // If we have medical records, append a hidden assistant message
                    if !selectedMedicalRecords.isEmpty {
                        let hiddenContent = "Medical records have been attached to this conversation. I'll use this information to provide more personalized assistance."
                        let hiddenMessage = ChatMessage(message: .assistant(content: .text(hiddenContent)), hidden: true)
                        chat.storeMessage(hiddenMessage)
                    }
                }
            }
        }
    }
    
    private func microphoneButtonPressed() {
        if speechRecognizer.isRecording {
            speechRecognizer.stop()
        } else {
            Task {
                do {
                    for try await result in speechRecognizer.start() {
                        if result.bestTranscription.formattedString.contains("send") {
                            sendMessage()
                        } else {
                            localInputText = result.bestTranscription.formattedString
                        }
                    }
                }
            }
        }
    }
    
    private func removeAttachment(at index: Int) {
        // Ensure we're on the main thread for UI updates
        DispatchQueue.main.async {
            let imageCount = selectedImages.count
            let fileCount = selectedFiles.count
            
            if index < imageCount {
                selectedImages.remove(at: index)
            } else if index < imageCount + fileCount {
                let fileIndex = index - imageCount
                selectedFiles.remove(at: fileIndex)
            } else {
                let medicalRecordIndex = index - imageCount - fileCount
                selectedMedicalRecords.remove(at: medicalRecordIndex)
            }
        }
    }
}

#Preview {
    AIMessageInputView()
        .padding()
        .environment(AIChat())
        .environment(HealthProfile())
        .preferredColorScheme(.dark)
} 
