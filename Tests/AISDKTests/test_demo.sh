#!/bin/bash

echo "AISDK Test Runner Script"
# AISDK Test Runner Script
# Usage: ./test_demo.sh [model_name_or_category] [test_category]

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🤖 AISDK Test Runner${NC}"
echo "=================================="

# Check for API key
if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${RED}❌ Please set OPENAI_API_KEY environment variable${NC}"
    echo "   export OPENAI_API_KEY=your_key_here"
    exit 1
fi

# Define known test categories
CATEGORIES=("llm" "agent" "multimodal" "thinking" "thinking-multimodal" "all")

# Parse parameters intelligently
PARAM1=${1:-"all"}
PARAM2=$2

# Check if first parameter is a known category
if [[ " ${CATEGORIES[@]} " =~ " ${PARAM1} " ]]; then
    # First parameter is a category
    TEST_CATEGORY=$PARAM1
    MODEL=${PARAM2:-"gpt-4o"}
else
    # First parameter is a model name
    MODEL=$PARAM1
    TEST_CATEGORY=${PARAM2:-"all"}
fi

echo -e "${YELLOW}📋 Configuration:${NC}"
echo "   Model: $MODEL"
echo "   Test Category: $TEST_CATEGORY"
echo "   API Key: ${OPENAI_API_KEY:0:10}..."
echo ""

# Export the model for tests to use
export TEST_MODEL=$MODEL

case $TEST_CATEGORY in
    "llm")
        echo -e "${BLUE}🧠 Running LLM Tests with $MODEL${NC}"
        swift test --filter BasicChatTests.testOpenAIIntegration --enable-test-discovery
        swift test --filter StreamingChatTests.testOpenAIIntegration --enable-test-discovery
        ;;
    "agent")
        echo -e "${BLUE}🤖 Running Agent Tests with $MODEL${NC}"
        swift test --filter AgentIntegrationTests --enable-test-discovery
        ;;
    "multimodal")
        echo -e "${BLUE}🖼️ Running Multimodal Tests with $MODEL${NC}"
        swift test --filter MultimodalTests.testOpenAI --enable-test-discovery
        ;;
    "thinking")
        echo -e "${BLUE}🧠 Running Thinking Model Tests${NC}"
        export TEST_MODEL="o4-mini"
        swift test --filter BasicChatTests.testOpenAIIntegration --enable-test-discovery
        swift test --filter StreamingChatTests.testOpenAIIntegration --enable-test-discovery
        ;;
    "thinking-multimodal")
        echo -e "${BLUE}🧠🖼️ Running Thinking Model + Multimodal Tests${NC}"
        export TEST_MODEL="o4-mini"
        echo -e "${YELLOW}Testing o4-mini with image analysis capabilities...${NC}"
        swift test --filter MultimodalTests.testOpenAI --enable-test-discovery
        ;;
    "all")
        echo -e "${BLUE}🚀 Running All Integration Tests with $MODEL${NC}"
        echo -e "${YELLOW}Phase 1: LLM Tests${NC}"
        swift test --filter BasicChatTests.testOpenAIIntegration --enable-test-discovery
        swift test --filter StreamingChatTests.testOpenAIIntegration --enable-test-discovery
        
        echo -e "${YELLOW}Phase 2: Multimodal Tests${NC}"
        swift test --filter MultimodalTests.testOpenAI --enable-test-discovery
        
        echo -e "${YELLOW}Phase 3: Agent Tests${NC}"
        swift test --filter AgentIntegrationTests --enable-test-discovery
        ;;
    *)
        echo -e "${RED}❌ Unknown test category: $TEST_CATEGORY${NC}"
        echo "Available categories: llm, agent, multimodal, thinking, thinking-multimodal, all"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}✅ Test run completed!${NC}"

# Usage examples
echo ""
echo -e "${YELLOW}💡 Usage Examples:${NC}"
echo "   # Test with o4-mini thinking model"
echo "   ./test_demo.sh o4-mini thinking"
echo ""
echo "   # Test thinking model with images"
echo "   ./test_demo.sh thinking-multimodal"
echo ""
echo "   # Test with gpt-4o-mini"
echo "   ./test_demo.sh gpt-4o-mini llm"
echo ""
echo "   # Test multimodal capabilities"
echo "   ./test_demo.sh gpt-4o multimodal"
echo ""
echo "   # Test with custom model"
echo "   ./test_demo.sh gpt-4o agent"
echo ""
echo "   # Test all with default model"
echo "   ./test_demo.sh" 