//
//  ConnectionView.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 16/03/25.
//


import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var chatContext: ChatContext

    @State private var isConnecting: Bool = false
    private var tokenService: TokenService = .init()

    var body: some View {
        if chatContext.isConnected {
            ChatView()
        } else {
            VStack(spacing: 24) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                
                Text("Hi I'm Cony, Your Personal Health Companion")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(
                    "Ready to help you track your health goals, answer medical questions, and provide personalized wellness advice. Let's start your journey to better health together!"
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                Button(action: {
                    Task {
                        isConnecting = true

                        let roomName = "room-\(Int.random(in: 1000 ... 9999))"
                        let participantName = "user-\(Int.random(in: 1000 ... 9999))"

                        do {
                            let connectionDetails = try await tokenService.fetchConnectionDetails(
                                roomName: roomName,
                                participantName: participantName
                            )

                            try await chatContext.connect(
                                url: connectionDetails.serverUrl,
                                token: connectionDetails.participantToken
                            )
                        } catch {
                            print("Connection error: \(error)")
                        }
                        isConnecting = false
                    }
                }) {
                    Text(isConnecting ? "Connecting..." : "Connect")
                        .font(.headline)
                        .frame(maxWidth: 280)
                        .animation(.none, value: isConnecting)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isConnecting)
            }
            .padding()
        }
    }
}


struct AutoConnectView: View {
    @EnvironmentObject private var chatContext: ChatContext
    @State private var isConnecting: Bool = false
    @Environment(\.dismiss) private var dismiss
    private var tokenService: TokenService = .init()

    var body: some View {
        VStack {
            if chatContext.isConnected {
                ChatView()
            } else {
                VStack(spacing: 24) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                    
                    Text("Connecting to AI Voice Mode...")
                        .font(.headline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)

                    ProgressView()
                        .controlSize(.large)
                    
                    Button("Cancel") {
                        isConnecting = false
                        dismiss()
                    }
                    .padding(.top, 24)
                }
                .padding()
                .onAppear {
                    initiateConnection()
                }
            }
        }
    }
    
    private func initiateConnection() {
        Task {
            isConnecting = true
            
            let roomName = "room-\(Int.random(in: 1000 ... 9999))"
            let participantName = "user-\(Int.random(in: 1000 ... 9999))"
            
            do {
                let connectionDetails = try await tokenService.fetchConnectionDetails(
                    roomName: roomName,
                    participantName: participantName
                )
                
                try await chatContext.connect(
                    url: connectionDetails.serverUrl,
                    token: connectionDetails.participantToken
                )
            } catch {
                print("Connection error: \(error)")
                // Show error alert or feedback here
                dismiss() // Go back on error
            }
            
            isConnecting = false
        }
    }
} 
