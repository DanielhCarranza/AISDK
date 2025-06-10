#!/bin/bash

echo "🧪 AISDK Testing Demo"
echo "===================="

echo ""
echo "📋 Available Tests:"
echo "1. Unit Tests (Mock Provider)"
echo "2. CLI Demo (Requires API Keys)"
echo ""

# Run unit tests
echo "🔄 Running Unit Tests..."
echo ""

echo "📝 Basic Chat Tests:"
swift test --filter BasicChatTests

echo ""
echo "🔄 Streaming Chat Tests:"
swift test --filter StreamingChatTests

echo ""
echo "🖼️ Phase 1: Multimodal Tests:"
swift test --filter MultimodalTests

echo ""
echo "📝 Phase 2: Structured Output Tests:"
swift test --filter StructuredOutputTests

echo ""
echo "✅ Unit Tests Complete!"
echo ""

echo "📋 CLI Demo Instructions:"
echo "To test with real API providers:"
echo "1. Create a .env file in the root directory"
echo "2. Add your API keys:"
echo "   OPENAI_API_KEY=your_openai_key_here"
echo "   CLAUDE_API_KEY=your_claude_key_here"
echo "3. Run: swift run BasicChatDemo"
echo ""

echo "🎉 Testing infrastructure is ready!"
echo "   - Mock provider for unit testing ✅"
echo "   - Basic chat completion tests ✅"
echo "   - Streaming chat tests ✅"
echo "   - CLI demo for real API testing ✅" 