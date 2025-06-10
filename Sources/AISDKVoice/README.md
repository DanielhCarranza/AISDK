# Conversational Voice Mode AI Feature

## Overview

The Conversational Voice AI feature is a powerful and interactive component of the HealthCompanion app. It provides users with a voice-based interface to interact with an AI health companion named Eliza. This feature combines speech recognition, natural language processing, and text-to-speech capabilities to create a seamless conversational experience.

## Key Components

1. `AIVoiceModeView`: The main SwiftUI view that presents the user interface for the voice interaction.
2. `AIVoiceMode`: The core class that manages the conversational logic, speech recognition, and audio playback.
3. `VoiceActivityDetector`: Component that handles automatic silence detection for improved speech recognition.

## Features

- Real-time speech recognition
- AI-powered responses using a large language model
- Text-to-speech conversion for AI responses
- Interactive UI with microphone and playback controls
- Personalized health companion based on user's health profile
- Automatic voice activity detection (VAD) for hands-free operation
- Visual feedback with Eliza animation during AI responses
- Integration with user's HealthProfile for personalized interactions

## How It Works

1. The view initializes with the user's health profile and sets up the AI system.
2. Users can start speaking by tapping the microphone button or waiting for voice activity detection.
3. The app automatically stops recording after detecting silence (3 seconds).
4. The AI processes the transcribed text along with the user's health context.
5. Eliza's response is displayed with an animation during playback.
6. The conversation continues automatically, with the microphone activating after each AI response.

## Setup and Usage

1. Ensure all required dependencies are installed (OpenAI, SpeziSpeechRecognizer, ChunkedAudioPlayer, etc.).
2. Initialize the `AIVoiceModeView` in your app's navigation structure.
3. The view will automatically start the conversation with an initial greeting from Eliza.
4. Users can interact by tapping the microphone button to speak and listening to Eliza's responses.

## Customization

- Modify the `SYSTEM_PROMPT_AI_COMPANION` localized string to adjust Eliza's personality and knowledge base.
- Update the `HealthProfile` class to include relevant user health information for more personalized interactions.

## Technical Details

- Speech Recognition: Uses `SpeziSpeechRecognizer` with voice activity detection
- AI Model: Integrates with OpenAI's API
- Audio Playback: Implements `ChunkedAudioPlayer` for streaming playback
- State Management: Uses Swift's new `@Observable` macro
- UI Feedback: Provides visual indicators for recording, thinking, and playback states

## Error Handling

The feature includes error handling for various scenarios, including:
- Speech recognition errors
- AI model communication errors
- Audio playback issues

Error messages are displayed to the user when necessary.

## Performance Considerations

- The feature uses streaming for both speech recognition and audio playback to minimize latency.
- Consider implementing caching mechanisms for frequently used AI responses to improve response times.

## Future Enhancements

- Implement voice activity detection to automatically start/stop recording.
- Add support for multiple languages and accents.
- Integrate with other health-related APIs for more comprehensive health advice.

## UI Components

- Microphone button with recording animation
- Play/Pause controls for AI responses
- Status text showing current system state
- Eliza animation during AI speech playback

## State Management

The system manages several states:
- Recording state (isRecording)
- AI processing state (aiThinking)
- Playback state (isPlaying, isPaused)
- Initialization state (isInitializing)


