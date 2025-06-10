//
//  AgentView.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 16/03/25.
//


import LiveKit
import LiveKitComponents
import SwiftUI

struct AgentView: View {
    @EnvironmentObject var chatContext: ChatContext
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if let agent = chatContext.agentParticipant {
                AgentAudioVisualizer(agent: agent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentAudioVisualizer: View {
    @EnvironmentObject var room: Room
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var agent: RemoteParticipant
    @State private var pulse = false
    @State private var animateVisualizer = false
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            
            ZStack {
                if let track = agent.firstAudioTrack {
                    OrbAudioVisualizer(
                        audioTrack: track,
                        colorScheme: colorScheme
                    )
                    .frame(width: size, height: size)
                    .opacity(animateVisualizer ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: animateVisualizer)
                    .onAppear {
                        animateVisualizer = true
                    }
                } else {
                    // Fallback when no audio track is available
                    PulsingCircle(
                        colorScheme: colorScheme,
                        size: size * 0.2
                    )
                    .opacity(pulse ? 1 : 0.2)
                    .animation(.easeInOut(duration: 0.5), value: pulse)
                    .onAppear {
                        withAnimation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                            pulse.toggle()
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct OrbAudioVisualizer: View {
    private let audioTrack: AudioTrack
    private let colorScheme: ColorScheme
    @StateObject private var audioProcessor: AudioProcessor
    
    @State private var isAnimating = false
    @State private var gradientRotation: Double = 0
    
    init(audioTrack: AudioTrack, colorScheme: ColorScheme) {
        self.audioTrack = audioTrack
        self.colorScheme = colorScheme
        _audioProcessor = StateObject(wrappedValue: AudioProcessor(track: audioTrack, bandCount: 8, isCentered: true))
    }
    
    // Brand colors based on the infinity logo
    private var primaryColor: Color { Color(red: 0.2, green: 0.4, blue: 0.9) } // Blue
    private var secondaryColor: Color { Color(red: 0.8, green: 0.2, blue: 0.8) } // Purple
    private var accentColor: Color { Color(red: 0.9, green: 0.3, blue: 0.6) } // Pink
    
    private var brandGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [primaryColor, secondaryColor, accentColor, primaryColor]),
            center: .center,
            startAngle: .degrees(gradientRotation),
            endAngle: .degrees(360 + gradientRotation)
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            
            ZStack {
                // Base soft glow
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    .frame(width: size * 0.85, height: size * 0.85)
                    .blur(radius: 15)
                
                // Dynamic ripple layers with brand colors
                ForEach(0..<audioProcessor.bands.count, id: \.self) { index in
                    let intensity = audioProcessor.bands[index]
                    let delay = Double(index) * 0.05
                    
                    Circle()
                        .strokeBorder(
                            brandGradient,
                            lineWidth: 1.5 + CGFloat(intensity) * 2
                        )
                        .opacity(0.2 + Double(intensity) * 0.6)
                        .frame(
                            width: size * (0.3 + CGFloat(intensity) * 0.6),
                            height: size * (0.3 + CGFloat(intensity) * 0.6)
                        )
                        .blur(radius: CGFloat(intensity) * 1.5)
                        .animation(.easeInOut(duration: 0.3).delay(delay), value: intensity)
                }
                
                // Enhanced central orb with brand colors
                ZStack {
                    // Base glow for the orb
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    .white.opacity(0.9),
                                    .white.opacity(0.3),
                                    .clear
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.25
                            )
                        )
                        .frame(
                            width: size * 0.4 * (0.8 + CGFloat(audioProcessor.averageIntensity) * 0.4),
                            height: size * 0.4 * (0.8 + CGFloat(audioProcessor.averageIntensity) * 0.4)
                        )
                        .blur(radius: 3)
                    
                    // Brand color overlay with subtle animation
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    primaryColor.opacity(0.2),
                                    secondaryColor.opacity(0.3),
                                    accentColor.opacity(0.2),
                                    .clear
                                ]),
                                center: .center,
                                startRadius: size * 0.05,
                                endRadius: size * 0.3
                            )
                        )
                        .frame(
                            width: size * 0.45 * (0.8 + CGFloat(audioProcessor.averageIntensity) * 0.4),
                            height: size * 0.45 * (0.8 + CGFloat(audioProcessor.averageIntensity) * 0.4)
                        )
                        .rotationEffect(.degrees(gradientRotation * 0.5))
                    
                    // Inner core with more vibrant brand colors
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    .white,
                                    .white.opacity(0.9),
                                    primaryColor.opacity(0.3),
                                    secondaryColor.opacity(0.2),
                                    .clear
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.15
                            )
                        )
                        .frame(
                            width: size * 0.3 * (0.8 + CGFloat(audioProcessor.averageIntensity) * 0.3),
                            height: size * 0.3 * (0.8 + CGFloat(audioProcessor.averageIntensity) * 0.3)
                        )
                    
                    // Subtle shimmer effect
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    primaryColor.opacity(0.0),
                                    secondaryColor.opacity(0.3),
                                    accentColor.opacity(0.3),
                                    primaryColor.opacity(0.0)
                                ]),
                                center: .center
                            )
                        )
                        .frame(
                            width: size * 0.35 * (0.8 + CGFloat(audioProcessor.averageIntensity) * 0.3),
                            height: size * 0.35 * (0.8 + CGFloat(audioProcessor.averageIntensity) * 0.3)
                        )
                        .rotationEffect(.degrees(-gradientRotation * 0.3))
                        .opacity(0.6)
                        .blur(radius: 2)
                }
                .animation(.spring(dampingFraction: 0.7), value: audioProcessor.averageIntensity)
                
                // Accent rings with brand gradient
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .strokeBorder(
                            brandGradient,
                            lineWidth: 0.5
                        )
                        .opacity(0.2 + (isAnimating ? 0.3 : 0))
                        .frame(
                            width: size * (0.2 + Double(i) * 0.15),
                            height: size * (0.2 + Double(i) * 0.15)
                        )
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 1.5 + Double(i) * 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.3),
                            value: isAnimating
                        )
                }
                
                // Subtle gradient overlay for depth
                Circle()
                    .fill(brandGradient)
                    .frame(width: size * 0.6, height: size * 0.6)
                    .opacity(0.1)
                    .blur(radius: 10)
            }
            .frame(width: size, height: size)
            .onAppear {
                isAnimating = true
                // Animate gradient rotation
                withAnimation(Animation.linear(duration: 10).repeatForever(autoreverses: false)) {
                    gradientRotation = 360
                }
            }
        }
    }
}

// Simple pulsing circle for when no audio is detected
struct PulsingCircle: View {
    let colorScheme: ColorScheme
    let size: CGFloat
    
    // Brand colors based on the infinity logo
    private var primaryColor: Color { Color(red: 0.2, green: 0.4, blue: 0.9) } // Blue
    private var secondaryColor: Color { Color(red: 0.8, green: 0.2, blue: 0.8) } // Purple
    private var accentColor: Color { Color(red: 0.9, green: 0.3, blue: 0.6) } // Pink
    
    @State private var gradientRotation: Double = 0
    
    private var brandGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [primaryColor, secondaryColor, accentColor, primaryColor]),
            center: .center,
            startAngle: .degrees(gradientRotation),
            endAngle: .degrees(360 + gradientRotation)
        )
    }
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                .frame(width: size * 1.5, height: size * 1.5)
                .blur(radius: 5)
            
            // Enhanced core with layered gradients
            ZStack {
                // Base glow
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                .white.opacity(0.8),
                                .white.opacity(0.3),
                                .clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.8
                        )
                    )
                    .frame(width: size, height: size)
                
                // Brand color overlay
                Circle()
                    .fill(brandGradient)
                    .frame(width: size * 1.1, height: size * 1.1)
                    .opacity(0.4)
                    .blur(radius: 2)
                
                // Inner core
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                .white,
                                primaryColor.opacity(0.5),
                                secondaryColor.opacity(0.3),
                                .clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.6
                        )
                    )
                    .frame(width: size * 0.8, height: size * 0.8)
            }
        }
        .onAppear {
            // Animate gradient rotation
            withAnimation(Animation.linear(duration: 10).repeatForever(autoreverses: false)) {
                gradientRotation = 360
            }
        }
    }
}

// Extension to add convenience computed property for AudioProcessor
extension AudioProcessor {
    var averageIntensity: Float {
        let sum = bands.reduce(0, +)
        return sum / Float(bands.count)
    }
}

#Preview {
    AgentView()
        .environmentObject(ChatContext())
}