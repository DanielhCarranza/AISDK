import SwiftUI

struct SuggestedQuestionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AIChatManager.self) private var manager
    let questions: [SuggestedQuestion]
    let isLoading: Bool
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .padding(.horizontal)
                } else {
                    ForEach(questions) { suggestion in
                        Button(action: {
                            manager.sendMessage(suggestion.question)
                        }) {
                            Text(suggestion.question)
                                .font(.footnote)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.secondary.opacity(0.2))
                                        .blur(radius: 2)
                                }
                                .foregroundColor(.white.opacity(0.8))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: questions.isEmpty ? 0 : 44)
        .opacity(manager.state.isProcessing ? 0 : 1)
        .animation(.easeInOut, value: manager.state.isProcessing)
        .animation(.easeInOut, value: questions)
    }
} 
