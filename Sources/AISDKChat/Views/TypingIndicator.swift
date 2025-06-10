import SwiftUI

struct TypingIndicator: View {
    let state: AgentState
    
    @State private var bounceOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .thinking:
                // "Thinking..." text
                Text("Thinking")
                    .foregroundColor(.white.opacity(0.4))
                    .font(.caption)
                
                // Bouncing dots
                HStack(spacing: 2) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 4, height: 4)
                            .offset(y: bounceOffset)
                            .animation(
                                Animation.easeInOut(duration: 0.5)
                                    .repeatForever()
                                    .delay(0.2 * Double(index)),
                                value: bounceOffset
                            )
                    }
                }
                
            case .executingTool(let name):
                // Tool execution indicator
                Image(systemName: "gear")
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(bounceOffset))
                    .animation(
                        Animation.linear(duration: 2.0)
                            .repeatForever(autoreverses: false),
                        value: bounceOffset
                    )
                
                Text(name)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white)
                
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            bounceOffset = state == .thinking ? -5 : 360
        }
    }
} 