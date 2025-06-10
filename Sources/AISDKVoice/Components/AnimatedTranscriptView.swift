import SwiftUI

struct AnimatedTranscriptView: View {
    let text: String
    let currentWordIndex: Int
    
    private var words: [String] {
        text.split(separator: " ").map(String.init)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .center, spacing: 4) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        Text(word)
                            .font(.title3)
                            .foregroundStyle(index == currentWordIndex ? .primary : .secondary)
                            .opacity(getOpacity(for: index))
                            .padding(.horizontal, 4)
                            .id(index)
                    }
                }
                .padding(.horizontal)
                .onChange(of: currentWordIndex) {
                    withAnimation {
                        proxy.scrollTo(currentWordIndex, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 150) // Limit the height of the scroll view
        }
    }
    
    private func getOpacity(for index: Int) -> Double {
        if index == currentWordIndex {
            return 1.0
        } else if index < currentWordIndex {
            return 0.4
        } else {
            return 0.7
        }
    }
}

#Preview {
    AnimatedTranscriptView(text: "This is a sample text for preview purposes", currentWordIndex: 2)
} 
