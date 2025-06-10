import SwiftUI
import PhotosUI
import AVKit
import Speech
import SpeziSpeechRecognizer
import AVFoundation

// Define the AI mode enum
enum AIChatMode {
    case chat      // Default mode, no button shown
    case journal
    case research
}

struct AIInputView: View {
    // MARK: - Environment & State
    
    @Environment(AIChatManager.self) private var chat
    @Environment(HealthProfile.self) private var healthProfile
    @Environment(\.researchAgent) private var researchAgent
    
    // Local state for text input with debouncing
    @State private var localInputText = ""
    @State private var debouncedTask: Task<Void, Never>?
    
    // Mode selection
    @State private var selectedMode: AIChatMode = .chat
    
    // Attachment states
    @State private var selectedImages: [ImagePreviewBar.ImageData] = []
    @State private var imageSelection: [PhotosPickerItem] = []
    @State private var selectedFiles: [URL] = []
    @State private var selectedMedicalRecords: [MedicalRecord] = []
    
    // UI state
    @State private var showingAttachmentMenu = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var showingFilePicker = false
    @State private var showingMedicalRecordsPicker = false
    @State private var showingVoiceMode = false
    @State private var isRecording = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var speechRecognizer = SpeechRecognizer()
    
    // Binding for visibility control
    @Binding var isVisible: Bool
    
    // Focus state
    @FocusState var isInputFocused: Bool
    
    // Minimum height for the text editor
    private let minTextEditorHeight: CGFloat = 40
    
    // Dynamic height based on content
    @State private var textEditorHeight: CGFloat = 40
    
    init(isFocused: FocusState<Bool> = FocusState<Bool>(), isVisible: Binding<Bool> = .constant(true)) {
        self._isInputFocused = isFocused
        self._isVisible = isVisible
    }
    
    // MARK: - Computed Properties
    
    private var isEntryValid: Bool {
        !localInputText.isEmpty || !selectedImages.isEmpty || !selectedFiles.isEmpty || !selectedMedicalRecords.isEmpty
    }
    
    private var placeholderText: String {
        switch selectedMode {
        case .chat:
            return "Ask a question..."
        case .journal:
            return "How do you feel today?"
        case .research:
            return "What would you like to research?"
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Attachment Preview
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
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: !selectedImages.isEmpty || !selectedFiles.isEmpty || !selectedMedicalRecords.isEmpty)
            }
            
            // Input Area with background
            VStack(spacing: 4) {
                // Tab bar
                HStack {
                    // Journal/Research tabs as small rounded buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            // Toggle between journal and chat mode
                            selectedMode = selectedMode == .journal ? .chat : .journal
                        }) {
                            Text("Journal")
                                .font(.footnote)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedMode == .journal ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                                .foregroundStyle(selectedMode == .journal ? .white : .white.opacity(0.7))
                                .cornerRadius(16)
                        }
                        
                        Button(action: {
                            // Toggle between research and chat mode
                            selectedMode = selectedMode == .research ? .chat : .research
                        }) {
                            Text("Research")
                                .font(.footnote)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedMode == .research ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                                .foregroundStyle(selectedMode == .research ? .white : .white.opacity(0.7))
                                .cornerRadius(16)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
                
                // Text input field
                TextField(placeholderText, text: $localInputText, axis: .vertical)
                    .font(.system(size: 16))
                    .frame(minHeight: textEditorHeight)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .focused($isInputFocused)
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
                    // Add performance optimizations
                    .transaction { transaction in
                        // Disable animations for text changes to improve performance
                        transaction.animation = nil
                    }
                
                // Toolbar
                HStack {
                    // Left toolbar - media options
                    HStack(spacing: 24) {
                        // attach files button
                        Button(action: {
                            showingAttachmentMenu = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.95))
                        }
                        .buttonStyle(ToolbarButtonStyle())
                        // Camera button
                        // Button(action: {
                        //     hapticFeedback(.medium)
                        //     showingCamera = true
                        // }) {
                        //     Image(systemName: "camera")
                        //         .font(.system(size: 18))
                        //         .foregroundStyle(.white.opacity(0.95))
                        // }
                        // .buttonStyle(ToolbarButtonStyle())
                        
                        // // Photo library button
                        // PhotosPicker(selection: $imageSelection, maxSelectionCount: 4, matching: .images) {
                        //     Image(systemName: "photo")
                        //         .font(.system(size: 18))
                        //         .foregroundStyle(.white.opacity(0.95))
                        // }
                        // .buttonStyle(ToolbarButtonStyle())
                        
                        // // Video button
                        // Button(action: {
                        //     hapticFeedback(.medium)
                        //     showingFilePicker = true
                        // }) {
                        //     Image(systemName: "video")
                        //         .font(.system(size: 18))
                        //         .foregroundStyle(.white.opacity(0.95))
                        // }
                        // .buttonStyle(ToolbarButtonStyle())
                    
                        
                    }
                    
                    Spacer()
                    
                    // Right toolbar - voice mode, mic, and send buttons
                    HStack(spacing: 20) {
                        Button(action: microphoneButtonPressed) {
                                    Image(systemName: "mic")
                                        .accessibilityLabel("Microphone Button")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white.opacity(0.95))
                                        .scaleEffect(speechRecognizer.isRecording ? 1.2 : 1.0)
                                        .opacity(speechRecognizer.isRecording ? 0.7 : 1.0)
                                        .animation(
                                            speechRecognizer.isRecording ? 
                                                .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : 
                                                .default,
                                            value: speechRecognizer.isRecording
                                        )
                                }
                                .buttonStyle(ToolbarButtonStyle())
                        
                        // Mic or send button
                        Group {
                            if chat.state.isProcessing {
                                Button(action: {
                                    chat.stopStreaming()
                                }) {
                                    Image(systemName: "stop.circle.fill")
                                        .accessibilityLabel("Stop Generation")
                                        .font(.system(size: 20))
                                        .foregroundColor(.red)
                                }
                            } else if speechRecognizer.isAvailable && (localInputText.isEmpty || speechRecognizer.isRecording) {
                                
                                // Voice mode button
                                Button(action: {
                                    showingVoiceMode = true
                                }) {
                                    ZStack {
                                        MeshGradientCircle()
                                            .frame(width: 28, height: 28)
                                        
                                        Image(systemName: "waveform.and.mic")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                    }
                                }
                                .buttonStyle(ToolbarButtonStyle())
                            } else {
                                Button(action: sendMessage) {
                                    Group {
                                        if chat.isUploading {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.up.circle.fill")
                                                .accessibilityLabel("Send Message")
                                                .font(.system(size: 20))
                                        }
                                    }
                                    .foregroundStyle(.white.opacity(0.95))
                                }
                                .disabled(!isEntryValid || chat.state.isProcessing || chat.isUploading)
                                .buttonStyle(ToolbarButtonStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .padding(.top, 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.black.opacity(0.2))
                    .background(.ultraThinMaterial)
                    .blur(radius: 3)
                    .cornerRadius(25, corners: [.topLeft, .topRight])
            )
        }
        .background(
            // Background tap area to dismiss keyboard
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isInputFocused = false
                }
        )
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        .onAppear {
            setupKeyboardObservers()
        }
        .onDisappear {
            removeKeyboardObservers()
        }
        .onChange(of: imageSelection) { _, newItems in
            handleImageSelection(newItems)
        }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            // Handle camera dismiss if needed
        }) {
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
        .navigationDestination(isPresented: $showingVoiceMode) {
            ChatContextProvider {
                AutoConnectView()
            }
        }
        .preference(key: ResearchModePreferenceKey.self, value: selectedMode == .research)
        .onChange(of: selectedMode) { oldValue, newValue in
            if newValue == .research {
                // When research mode is selected
                print("Research mode selected")
            }
        }
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        let text = localInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !text.isEmpty || !selectedImages.isEmpty || !selectedFiles.isEmpty || !selectedMedicalRecords.isEmpty {
            print("📎 Sending message with \(selectedImages.count) images, \(selectedFiles.count) files, and \(selectedMedicalRecords.count) medical records")
            
            isInputFocused = false
            isVisible = false // Hide the input view after sending
            
            // Handle research mode differently
            if selectedMode == .research, let researchAgent = researchAgent {
                // Start research with the ResearcherAgent
                researchAgent.startResearch(topic: text)
                
                // Clear input fields
                localInputText = ""
                selectedImages = []
                selectedFiles = []
                selectedMedicalRecords = []
                
                // Make input visible again after sending
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isVisible = true
                }
                return
            }
            
            // Determine required tool based on mode
            let requiredTool: String? = selectedMode == .journal ? "log_journal" : nil
            
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
                    chat.sendMessage(parts, attachments: messageAttachments, requiredTool: requiredTool)
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
                    
                    // Make input visible again after sending
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isVisible = true
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
    
    // Handle image selection from PhotosPicker
    private func handleImageSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        
        Task {
            for item in items {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            selectedImages.append(ImagePreviewBar.ImageData(data: data))
                        }
                    }
                } catch {
                    print("Failed to load image: \(error)")
                }
            }
        }
    }
    
    // Remove attachment at specific index
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
    
    // Provide haptic feedback
    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    // Keyboard management
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let window = UIApplication.shared.windows.first else {
                return
            }
            
            let keyboardHeight = keyboardFrame.height - window.safeAreaInsets.bottom
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? UIView.AnimationCurve.easeInOut.rawValue
            
            // Map UIKit animation curve to SwiftUI animation
            var animation: Animation = .easeOut(duration: duration)
            switch curveValue {
            case UIView.AnimationCurve.easeIn.rawValue:
                animation = .easeIn(duration: duration)
            case UIView.AnimationCurve.easeOut.rawValue:
                animation = .easeOut(duration: duration)
            case UIView.AnimationCurve.easeInOut.rawValue:
                animation = .easeInOut(duration: duration)
            case UIView.AnimationCurve.linear.rawValue:
                animation = .linear(duration: duration)
            default:
                animation = .easeOut(duration: duration)
            }
            
            withAnimation(animation) {
                self.keyboardHeight = keyboardHeight
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.keyboardHeight = 0
        }
    }
    
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
}

// Environment key for ResearcherAgent
struct ResearchAgentKey: EnvironmentKey {
    static let defaultValue: ResearcherAgent? = nil
}

extension EnvironmentValues {
    var researchAgent: ResearcherAgent? {
        get { self[ResearchAgentKey.self] }
        set { self[ResearchAgentKey.self] = newValue }
    }
}

#Preview {
    AIInputView()
        .padding()
        .environment(AIChatManager())
        .environment(HealthProfile())
        .preferredColorScheme(.dark)
} 
