//
//  ChatHistoryView.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 24/12/24.
//

import SwiftUI

struct ChatHistoryView: View {
    @Environment(AIChatManager.self) var manager
    @Binding var isPresented: Bool
    
    var body: some View {
        Group {
            if manager.isLoading {
                VStack {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading chats...")
                        .foregroundColor(.secondary)
                }
            } else if manager.chatSessions.isEmpty {
                ContentUnavailableView {
                    Label("No Chats", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start a new chat to begin")
                } actions: {
                    Button(action: {
                        Task {
                            await manager.createNewSession()
                        }
                        isPresented = false
                    }) {
                        Text("New Chat")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("CONVERSATIONS")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button {
                            Task {
                                await manager.createNewSession()
                            }
                            isPresented = false
                        } label: {
                            HStack(spacing: 4) {
                                Text("New")
                                Image(systemName: "plus")
                            }
                            .fontWeight(.semibold)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    
                    List {
                        ForEach(manager.chatSessions.sorted(by: { $0.lastModified > $1.lastModified })) { session in
                            if session.id != nil {
                                ChatSessionRow(session: session, isPresented: $isPresented)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Text("")  // Empty text to remove default title
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "chevron.right.2")
                        .fontWeight(.semibold)
                }
            }
        }
        .task {
            // Load chat sessions when view appears
            manager.loadAllSessions()
        }
    }
}

struct ChatSessionRow: View {
    @Environment(AIChatManager.self) var manager
    let session: ChatSession
    @Binding var isPresented: Bool
    @State private var showingDeleteAlert = false
    @State private var showingEditTitleAlert = false
    @State private var editedTitle = ""
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(formatDate(session.lastModified))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .onTapGesture {
            manager.loadSession(session)
            isPresented = false
        }
        .contextMenu {
            Button {
                editedTitle = session.title
                showingEditTitleAlert = true
            } label: {
                Label("Edit Title", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Chat", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                manager.deleteSession(session)
            }
        } message: {
            Text("Are you sure you want to delete this chat? This action cannot be undone.")
        }
        .alert("Edit Title", isPresented: $showingEditTitleAlert) {
            TextField("Title", text: $editedTitle)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if !editedTitle.isEmpty {
                    manager.updateSessionTitle(session, newTitle: editedTitle)
                }
            }
        } message: {
            Text("Enter a new title for this chat")
        }
    }
    
    // Format date to show day of week for recent dates or date for older ones
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day of week
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return formatter.string(from: date)
        }
    }
} 
