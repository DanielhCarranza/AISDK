# Personal AI Health Companion Chat Feature

The Personal AI Health Companion Chat feature delivers an intelligent, context-aware conversational experience that helps patients interact with their health data and ask health-related questions. It seamlessly integrates advanced LLM (Large Language Model) responses with tool-based functionality and dynamic system prompts to create a rich and responsive chat environment.

---

## Overview

The chat feature is designed to:
- **Engage Users in Real Time:** Users interact through a dynamic chat interface that supports text, voice, and image attachments.
- **Manage Conversations Effectively:** Each conversation is maintained as a session with full history, automatic title generation, and real-time updates.
- **Provide Contextual and Personalized Responses:** System prompts are modified based on dynamic modes (such as observer mode triggered by events) and the user's health profile.
- **Offer Intelligent Follow-Up Suggestions:** When idle, the system generates suggested questions that help the patient further explore their concerns.

---

## Key Features

### Chat Session Management
- **New Session Creation:**
  - **Automatic Initialization:** If no chat sessions exist, the system creates a new session automatically.
  - **Unsaved Session State:** A new session is maintained in memory until the first user message is sent to avoid storing empty sessions.
  - **Default System Prompt:** A system message is added based on the current mode (e.g., standard chat or observer mode) and enriched with the user's health profile.
- **Existing Session Selection:**
  - **Real-Time Updates:** Chat sessions are fetched and updated in real time from the database.
  - **Local Caching:** The most recent or last active session is cached using UserDefaults for a seamless user experience.
- **Session Title Generation:**
  - **Automatic Title:** After the first user message is sent, the agent generates a concise title (maximum of 5 words) by analyzing the conversation context.
  - **Metadata Storage:** The generated title is stored in the session metadata and displayed in the session list.
- **Session Deletion:**
  - **Clean Removal:** Deleting a session removes it from both the UI and the database.
  - **Fallback Creation:** If the current session is deleted, a new session is automatically created to ensure continuity.

### Messaging Interface

- **Conversation View:**
  - **Scrollable Message History:** Messages are displayed in a scrollable list with distinct bubble styles for user, assistant, and system messages.
  - **Real-Time Updates:** When the assistant streams its reply, partial messages are updated live until completion.
- **Message Input View:**
  - **Text Entry:** A multi-line text field supports dynamic input and adapts to keyboard events.
  - **Attachment Options:** An attachment button allows users to add images (via the camera or photo library), files, or other media.
  - **Voice Input:** A microphone button integrates with speech recognition, letting users dictate their messages.
  - **Dynamic Controls:** Depending on state, the input view shows:
    - A **send button** (for normal message submission),
    - A **stop button** (to cancel streaming responses), or
    - A **microphone button** (when voice input is active).
- **Suggested Questions:**
  - **Context-Aware Prompts:** When the assistant is idle, the system generates two relevant follow-up questions based on the conversation.
  - **Display Above Input:** These suggestions are shown above the input view, encouraging further engagement.

### Assistant Response Handling

- **Non-Streaming Responses:**
  - The assistant's final reply is received as a complete message and is immediately appended to the conversation.
- **Streaming Responses:**
  - **Pending Message:** A placeholder assistant message is created at the start of streaming.
  - **Real-Time Updates:** As partial tokens are received, the pending message is updated in real time.
  - **Completion:** Once streaming completes, the final message is stored in the session.
- **Tool Execution:**
  - **Detection & Execution:** If the assistant's response includes tool calls (e.g., for medical evidence search or health event management), the tool is executed and its output is integrated into the conversation.
  - **Multi-Chuck Streaming:** For tool calls that are streamed over multiple chunks, partial updates are accumulated and processed until the full response is available.

### System Prompt & Context Integration

- **Dynamic Modes:**
  - **Observer Mode:** When a trigger event (such as an urgent health context) is detected, the system prompt is modified to include specific context instructions.
  - **Standard Chat Mode:** In normal interactions, the system prompt adheres to the default companion guidelines.
- **Health Profile Integration:**
  - The user's health profile is automatically retrieved and displayed as part of the system messages to provide personalized context.
- **Prompt Customization:**
  - **Dynamic Messages:** Depending on trigger events or dynamic messages passed during session creation, the system prompt adapts to guide the conversation appropriately.

---

## User Experience Flow

### 1. Session Initialization
- **No Existing Sessions:**
  - On first launch or when no sessions exist, the app automatically creates a new session.
  - A system message with the default prompt (modified by mode and enriched with the health profile) is added.
  - An initial assistant message (or dynamic message) welcomes the user.
- **Existing Sessions:**
  - Chat History section where the user can see all the previous conversations

### 2. Sending a Message
- **User Action:**
  - The user types a message in the input view or uses voice input.
  - Attachments (e.g., photos) can be added using the attachment menu.
- **Immediate Storage:**
  - Upon sending, the message is immediately stored in the current session.
- **Assistant Response:**
  - The agent sends the user's message to the LLM.
  - For streaming responses, a pending assistant message is created and updated live.
  - For non-streaming responses, the final assistant message is appended directly.

### 3. Title Generation
- After the first user message is sent, the agent asynchronously generates a session title based on the conversation's context.
- This title is updated in the session metadata and displayed in the session list, making it easier for users to identify conversations.

### 4. Suggested Follow-Up Questions
- When the assistant is idle, the agent generates two follow-up questions that a patient might naturally ask.
- These suggested questions appear above the input view to prompt further inquiry and facilitate engagement.

### 5. Session Deletion and Renewal
- **Deleting a Session:**
  - When a user deletes a session, it is immediately removed from both the UI and the database.
  - If the deleted session was the current active session, the system automatically creates a new session.
- **New Session Creation:**
  - A new session is initiated with the default system prompt and health profile messages.
  - The new session remains unsaved until the first user message is sent, preventing empty sessions from cluttering storage.

---


## 1. High-Level Experience

1. **Chat Home*  
  - On first launch or when no sessions exist, the app automatically creates a new session.
  - A system message with the default prompt (modified by mode and enriched with the health profile) is added.
  - An initial assistant message (or dynamic message) welcomes the user.

2. **Chat history: Existing Sessions**  
  - Chat History section where the user can see all the previous conversations

3. **In-Chat Experience**  
   - Each session shows a timeline of messages from the user and the AI assistant (plus system messages).  
   - The **message input** field is at the bottom, where users can:
     - Type text questions
     - Attach images
     - (Optionally) switch to voice input

4. **AI Responses**  
   - The AI **streams** its responses token by token (like typing) for a more natural effect.  
   - User sees partial text updates as they arrive.  

5. **Suggested Questions**  
   - After the AI responds, the system can show **short suggested follow-up questions** to help users continue the conversation more easily.  

6. **Session Management**  
   - Each session's conversation is stored in DB.  
   - **Deleting** a session removes it from DB.  
   - **No existing sessions**? Automatically create a new one.  

---

## 2. Key Components

### 2.1 Chat Sessions

- A `ChatSession` is the container for a conversation. It includes:
  - `id` (Firestore Document ID)
  - `title` (short description)
  - `messages` (array of `ChatMessage`)
  - `createdAt`, `lastModified` timestamps

- **Lifecycle**:  
  1. When the user first creates a session, it might start off as "unsaved" (no Firestore doc).
  2. As soon as the user sends their first message, we generate a title and save it in the database.

### 2.2 Messages & Streaming

- Each user or assistant exchange is a `ChatMessage`.  
- **Message roles** can be:
  - `.system` (instructions to the AI)
  - `.user` (user input)
  - `.assistant` (AI output)
  - `.tool` (debug or specialized tool responses)
  - `.developer` (additional development instructions)

- **Streaming** allows partial tokens to be displayed in real time. This means that **assistant messages** appear gradually rather than all at once.

### 2.3 AIChatManager

- Central manager for the chat feature.  
- Responsible for:
  - **Loading sessions** from Firestore
  - **Creating** and **storing** new sessions
  - **Sending messages** (text & images) to the AI
  - **Streaming** partial AI responses
  - Generating **suggested follow-up questions**
  - Maintaining overall state (e.g., `isStreaming`, `isUploading`, `state`)

### 2.4 AIConversationView

- The main **SwiftUI** view showing a single chat session:
  1. Displays the **list of messages** in a scrollable view.
  2. Integrates the **message input** at the bottom.
  3. Optionally shows a "scroll to bottom" button if the user scrolls away.
  4. Automatically updates with streaming messages in real-time.

### 2.5 AIMessageInputView

- A **SwiftUI** view responsible for:
  - The **text field** where the user types a message.
  - The **send/stop button** that:
    - Shows as send (paper airplane) when ready to send
    - Changes to stop (X) during streaming
    - Returns to send after streaming ends
  - An **attachment** button to pick images or other media.
  - **Voice Mode** entry point (for advanced voice interactions).

---

## 3. Detailed Flow

### 3.1 Loading Sessions

1. On app load or feature entry:
   - The `AIChatManager` fetches last session from cache first, then from DB, then it fetches all sessions from DB. so when the users opens the chat history it shows the list of sessions.
   - If there is a previously active session (cached in `UserDefaults`), the manager attempts to load it.
   - If no sessions exist, the manager immediately [creates a new session](#creating-a-new-session).

2. **UI**: The user sees an initial `AIConversationView` with a welcome message from the AI if there is no session, if there is a session it shows the chat history.

### 3.2 Creating a New Session

1. **Triggers**:
   - User manually taps "New Chat" in the session list.
   - Or the system detects no existing session in Firestore.
2. **Process**:
   - A blank `ChatSession` is prepared in memory.
   - Prepend any relevant **system messages** (like `SYSTEM_PROMPT_AI_COMPANION` or context from a medical event).
   - Immediately insert an **assistant** message with a welcome or relevant introduction.  
   - This new session is "unsaved" until the user actually sends a message.
3. **UX**:
   - In the UI, the user sees the brand-new conversation with an initial greeting from the AI, but it's not in Firestore yet.
   - Once the user **sends** their first message, the manager:
     - Invokes **title generation** (analyzing the conversation to propose a short name).
     - Saves the session to Database with that title.

### 3.3 Storing & Updating Chat History

- Every time the user sends a message:
  1. We create a `ChatMessage` with `.user` role.
  2. Immediately **append** it to the `ChatSession.messages`.
  3. If the session is unsaved, we do the "generate title & save to Database" step. Otherwise, we update the existing doc.

- For **assistant** messages (which can arrive in chunks if streaming):
  1. We store the final chunk once streaming completes.
  2. Partial updates (token-by-token) are not fully saved to Database each time. Instead, we keep them in memory to show on screen. Once the final message arrives, we commit it to Database.

- This ensures we do not fill the database with many partial updates.

### 3.4 Generating Suggested Questions

- After an AI response is complete (i.e., the state changes back to `.idle`):
  - `AIChatManager` calls `generateSuggestedQuestions()`.
  - It sends a small prompt to the AI (or a smaller model) to propose **2 short** follow-up user questions based on the conversation.
  - The result is displayed as **inline suggestions** above the input field.
- **UX**: The user can tap a suggested question to quickly send it, or type their own text.

### 3.5 Streaming Responses

1. When user taps **Send**:
   - We add a temporary "pending" assistant message to the UI.
   - `AIChatManager` calls `agent.sendStream(...)`, which yields partial tokens in an `AsyncThrowingStream`.
2. Each partial token:
   - Is appended to the pending message text.
   - Displayed immediately for real-time reading.
3. **Stop Streaming**:
   - While streaming, the send button changes to a stop button.
   - If user taps stop:
     - The current streaming task is cancelled.
     - The partial response is kept and marked as complete.
     - The message is saved to the database in its current state.
4. When the stream finishes (naturally or via stop):
   - We finalize the assistant message, storing it in Database.  
   - The pending indicator is removed, and the conversation is now fully updated.
   - The stop button changes back to send button.

### 3.6 Handling Attachments (Images)

- The user taps **Add Attachment** (`plus.circle.fill`):
  - Shown a menu with options (camera, photo library, medical records, etc.).
- Selected images are **previewed** in a horizontal bar above the input text field.  
- When user taps **Send**, the manager:
  1. Uploads images asynchronously to Firebase Storage.
  2. Retrieves each image URL and appends it as an `.imageURL` part of the message.
  3. Creates a `.user` message with text + images combined in `[.text("..."), .imageURL(...)]`.
  4. The rest of the conversation proceeds normally.

### 3.7 Title Generation

- A short conversation title is generated by the AI after the first user message is sent in a new session.  
- The prompt is minimal, telling the AI:
  > "Generate a short title (max 5 words) summarizing the main topic."  
- The resulting string is stored in `ChatSession.title`.

### 3.8 Deleting a Session

- The user can delete a session from the chat list.  
- The manager calls `database.deleteData(...)` for that Firestore document ID.  
- If the user is **in** the session being deleted:
  - The manager checks if there are still sessions left.
    - If any remain, it loads the newest one.
    - Otherwise, it creates a new session on next chat initiation.

---

## 4. Voice Mode

- **Voice Mode** is accessed via the microphone icon in the input area.  
---

## 5. Error Handling

- **Network or AI Errors**:  
  - Show an error banner or text in the chat (e.g., red message).  
  - The user can retry sending the message if needed.
- **Tool Execution Errors**:  
  - If an AI "tool call" fails, we show a short error in the chat bubble.
- **Image Upload Failures**:  
  - The user sees a progress indicator. If upload fails, an error is displayed, and the user can retry.

---

## 6. UX Tips & Best Practices

1. **Non-blocking UI**:
   - The user can stop streaming responses at any time.
   - The stop button is clearly visible during streaming.
   - After stopping, the partial response is preserved and saved.
   - The user can attach more images or type while the AI is streaming.  
   - Keep the chat input accessible, but prevent overlapping or confusing states.

2. **Stream vs. Non-Stream**:
   - Streaming fosters a more natural, "typing out" feel.  
   - If performance or cost is a concern, you can switch to non-streaming for shorter replies.

3. **Suggested Questions**:
   - Provide hints to keep the conversation flowing naturally.  
   - Keep them short (max 8 words).  

4. **Empty States**:
   - If no sessions exist, automatically start a new one.  
   - Provide a clear "start chatting" message.

5. **Accessibility**:
   - Ensure voice dictation features are inclusive.  
   - Provide large hit targets for tapping suggestions or attachments.

---



