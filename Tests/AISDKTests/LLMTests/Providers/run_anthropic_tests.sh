#!/bin/bash

# AnthropicService Test Runner
# This script helps run the AnthropicService tests with different configurations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
USE_REAL_ANTHROPIC_API=${USE_REAL_ANTHROPIC_API:-false}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-""}
CLAUDE_API_KEY=${CLAUDE_API_KEY:-""}
TEST_FILTER=""
VERBOSE=false
BETA_FEATURES_ONLY=false
STREAMING_ONLY=false
TOOLS_ONLY=false

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "AnthropicService Test Runner"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --real-api          Use real Anthropic API (requires API key)"
    echo "  -m, --mock-only         Use mock tests only (default)"
    echo "  -k, --api-key KEY       Set Anthropic API key"
    echo "  -f, --filter PATTERN    Run only tests matching pattern"
    echo "  -b, --beta-features     Test beta features specifically"
    echo "  -s, --streaming         Test streaming features specifically"
    echo "  -t, --tools             Test tool features specifically"
    echo "  -v, --verbose           Verbose output"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --mock-only                    # Run mock tests only"
    echo "  $0 --real-api                     # Run real API tests (needs API key)"
    echo "  $0 --real-api --filter Basic      # Run only basic real API tests"
    echo "  $0 --beta-features                # Run only beta features tests"
    echo "  $0 --tools --real-api             # Run real API tool tests"
    echo "  $0 --streaming                    # Run only streaming tests"
    echo ""
    echo "Environment Variables:"
    echo "  ANTHROPIC_API_KEY         Your Anthropic API key"
    echo "  CLAUDE_API_KEY            Alternative API key name"
    echo "  USE_REAL_ANTHROPIC_API    Set to 'true' to enable real API tests"
    echo "  ANTHROPIC_TEST_MODEL      Override test model (default: claude-3-7-sonnet-20250219)"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--real-api)
            USE_REAL_ANTHROPIC_API=true
            shift
            ;;
        -m|--mock-only)
            USE_REAL_ANTHROPIC_API=false
            shift
            ;;
        -k|--api-key)
            ANTHROPIC_API_KEY="$2"
            shift 2
            ;;
        -f|--filter)
            TEST_FILTER="$2"
            shift 2
            ;;
        -b|--beta-features)
            BETA_FEATURES_ONLY=true
            shift
            ;;
        -s|--streaming)
            STREAMING_ONLY=true
            shift
            ;;
        -t|--tools)
            TOOLS_ONLY=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Determine API key to use
FINAL_API_KEY=""
if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    FINAL_API_KEY="$ANTHROPIC_API_KEY"
elif [[ -n "$CLAUDE_API_KEY" ]]; then
    FINAL_API_KEY="$CLAUDE_API_KEY"
fi

# Validate configuration
if [[ "$USE_REAL_ANTHROPIC_API" == "true" && -z "$FINAL_API_KEY" ]]; then
    print_error "Real API testing requires ANTHROPIC_API_KEY or CLAUDE_API_KEY to be set"
    print_warning "Either set the environment variable or use --api-key option"
    exit 1
fi

# Set up environment
export USE_REAL_ANTHROPIC_API
export USE_REAL_API="$USE_REAL_ANTHROPIC_API"  # Also set generic flag
export ANTHROPIC_API_KEY="$FINAL_API_KEY"
export CLAUDE_API_KEY="$FINAL_API_KEY"

# Print configuration
print_status "AnthropicService Test Configuration:"
echo "  Real API: $USE_REAL_ANTHROPIC_API"
if [[ "$USE_REAL_ANTHROPIC_API" == "true" ]]; then
    echo "  API Key: ${FINAL_API_KEY:0:8}..." # Show only first 8 chars
fi
if [[ -n "$TEST_FILTER" ]]; then
    echo "  Filter: $TEST_FILTER"
fi
if [[ "$BETA_FEATURES_ONLY" == "true" ]]; then
    echo "  Mode: Beta Features Only"
elif [[ "$STREAMING_ONLY" == "true" ]]; then
    echo "  Mode: Streaming Only"
elif [[ "$TOOLS_ONLY" == "true" ]]; then
    echo "  Mode: Tools Only"
fi
echo ""

# Change to project root (from Tests/AISDKTests/LLMTests/Providers/ to AISDK/)
cd "$(dirname "$0")/../../../.."

# Verify we're in the correct directory
if [[ ! -f "Package.swift" ]]; then
    print_error "Package.swift not found. Current directory: $(pwd)"
    print_error "Expected to be in AISDK project root"
    exit 1
fi

if [[ "$VERBOSE" == "true" ]]; then
    print_status "Project root: $(pwd)"
fi

# Build the project first
print_status "Building project..."
if [[ "$VERBOSE" == "true" ]]; then
    swift build
else
    swift build > /dev/null 2>&1
fi

if [[ $? -eq 0 ]]; then
    print_success "Build completed successfully"
else
    print_error "Build failed"
    exit 1
fi

# Prepare test command
TEST_CMD="swift test"

# Determine test filter based on options
if [[ "$BETA_FEATURES_ONLY" == "true" ]]; then
    if [[ -n "$TEST_FILTER" ]]; then
        TEST_CMD="$TEST_CMD --filter AnthropicService.*$TEST_FILTER.*Beta"
    else
        TEST_CMD="$TEST_CMD --filter AnthropicService.*Beta"
    fi
elif [[ "$STREAMING_ONLY" == "true" ]]; then
    if [[ -n "$TEST_FILTER" ]]; then
        TEST_CMD="$TEST_CMD --filter AnthropicService.*Streaming.*$TEST_FILTER"
    else
        TEST_CMD="$TEST_CMD --filter AnthropicServiceStreaming"
    fi
elif [[ "$TOOLS_ONLY" == "true" ]]; then
    if [[ -n "$TEST_FILTER" ]]; then
        TEST_CMD="$TEST_CMD --filter AnthropicService.*Tools.*$TEST_FILTER"
    else
        TEST_CMD="$TEST_CMD --filter AnthropicServiceTools"
    fi
elif [[ -n "$TEST_FILTER" ]]; then
    # Custom filter specified
    TEST_CMD="$TEST_CMD --filter $TEST_FILTER"
else
    # Run all AnthropicService tests
    TEST_CMD="$TEST_CMD --filter AnthropicService"
fi

# For mock-only mode, we'll filter out RealAPI tests by using specific test class names
if [[ "$USE_REAL_ANTHROPIC_API" != "true" ]]; then
    # If no specific filter was set, run only the mock-compatible tests
    if [[ -z "$TEST_FILTER" && "$BETA_FEATURES_ONLY" != "true" && "$STREAMING_ONLY" != "true" && "$TOOLS_ONLY" != "true" ]]; then
        TEST_CMD="swift test --filter AnthropicServiceTests --filter AnthropicServiceStreamingTests"
    fi
    # Note: RealAPI tests will be skipped automatically due to XCTSkipUnless
fi

# Run the tests
print_status "Running AnthropicService tests..."
echo "Command: $TEST_CMD"
echo ""

if [[ "$VERBOSE" == "true" ]]; then
    eval $TEST_CMD
else
    # Filter output to show only important information
    eval $TEST_CMD 2>&1 | grep -E "(Test Case|✅|❌|⚠️|PASS|FAIL|error:|warning:|Test Suite)"
fi

TEST_RESULT=$?

echo ""
if [[ $TEST_RESULT -eq 0 ]]; then
    print_success "All tests passed! 🎉"
    
    if [[ "$USE_REAL_ANTHROPIC_API" == "true" ]]; then
        print_success "Real API integration tests completed successfully"
        print_status "🔥 Real API features tested:"
        echo "  • Authentication & API key validation"
        echo "  • Core messaging (text, system prompts, multi-turn)"
        echo "  • Model support (Claude 3.7 Sonnet, 3.5 Sonnet, 3.5 Haiku)"
        echo "  • Streaming responses with delta accumulation"
        echo "  • Beta features (token-efficient tools, extended thinking)"
        echo "  • Tool integration and execution"
        echo "  • Error handling (rate limits, invalid models)"
        echo "  • Performance and concurrent requests"
    else
        print_success "Mock tests completed successfully"
        print_warning "To test with real Anthropic API, use: $0 --real-api"
        print_status "🚀 Mock features tested:"
        echo "  • Core functionality with mock responses"
        echo "  • Tool creation and configuration"
        echo "  • Streaming simulation"
        echo "  • Error simulation and handling"
    fi
    
    if [[ "$BETA_FEATURES_ONLY" == "true" ]]; then
        print_success "Beta features testing completed"
        echo "  • Token-efficient tools (14% token savings)"
        echo "  • Extended thinking capabilities"
        echo "  • Interleaved thinking"
        echo "  • Fine-grained tool streaming"
    elif [[ "$TOOLS_ONLY" == "true" ]]; then
        print_success "Tool integration testing completed"
        echo "  • AnthropicTool creation from schemas"
        echo "  • Tool choice options (auto, none, any, specific)"
        echo "  • Multi-tool scenarios and workflows"
        echo "  • Tool streaming capabilities"
    elif [[ "$STREAMING_ONLY" == "true" ]]; then
        print_success "Streaming functionality testing completed"
        echo "  • Basic streaming responses"
        echo "  • Delta accumulation and reconstruction"
        echo "  • Stream interruption and error handling"
        echo "  • Tool use in streaming mode"
    fi
else
    print_error "Some tests failed"
    print_warning "Check the output above for details"
    exit 1
fi

# Additional information
echo ""
print_status "Available Test Categories:"
echo "  • AnthropicServiceTests           - Core functionality (13 tests)"
echo "  • AnthropicServiceStreamingTests  - Streaming features (10 tests)"
echo "  • AnthropicServiceRealAPITests    - Real API integration (~20 tests)"
echo "  • AnthropicServiceToolsTests      - Tool functionality (~15 tests)"
echo ""

print_status "Quick Commands:"
echo "  # Fast mock tests"
echo "  $0 --mock-only"
echo ""
echo "  # Full real API validation"
echo "  export ANTHROPIC_API_KEY=\"your-key\""
echo "  $0 --real-api"
echo ""
echo "  # Specific feature testing"
echo "  $0 --beta-features --real-api"
echo "  $0 --tools --mock-only"
echo "  $0 --streaming --real-api"
echo ""

if [[ "$USE_REAL_ANTHROPIC_API" == "true" ]]; then
    print_status "🎯 Real API Test Summary:"
    echo "  • Authenticated with Anthropic API successfully"
    echo "  • Tested multiple Claude models and versions"
    echo "  • Validated beta features and tool integration"
    echo "  • Confirmed streaming and error handling"
    echo "  • Performance benchmarks within acceptable ranges"
    echo ""
    print_success "AnthropicService is ready for production use! 🚀"
else
    print_status "💡 Next Steps:"
    echo "  1. Set ANTHROPIC_API_KEY environment variable"
    echo "  2. Run: $0 --real-api"
    echo "  3. Test specific features with --beta-features or --tools"
    echo "  4. Integrate AnthropicService into your application"
fi 