#!/bin/bash

# OpenAI Responses API Test Runner
# This script helps run the OpenAI Responses API tests with different configurations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
USE_REAL_API=${USE_REAL_API:-false}
OPENAI_API_KEY=${OPENAI_API_KEY:-""}
TEST_FILTER=""
VERBOSE=false

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
    echo "OpenAI Responses API Test Runner"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --real-api          Use real OpenAI API (requires OPENAI_API_KEY)"
    echo "  -m, --mock-only         Use mock tests only (default)"
    echo "  -k, --api-key KEY       Set OpenAI API key"
    echo "  -f, --filter PATTERN    Run only tests matching pattern"
    echo "  -v, --verbose           Verbose output"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --mock-only                    # Run mock tests only"
    echo "  $0 --real-api                     # Run real API tests (needs API key)"
    echo "  $0 --real-api --filter Basic      # Run only basic real API tests"
    echo "  $0 --filter Streaming             # Run only streaming tests"
    echo ""
    echo "Environment Variables:"
    echo "  OPENAI_API_KEY    Your OpenAI API key"
    echo "  USE_REAL_API      Set to 'true' to enable real API tests"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--real-api)
            USE_REAL_API=true
            shift
            ;;
        -m|--mock-only)
            USE_REAL_API=false
            shift
            ;;
        -k|--api-key)
            OPENAI_API_KEY="$2"
            shift 2
            ;;
        -f|--filter)
            TEST_FILTER="$2"
            shift 2
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

# Validate configuration
if [[ "$USE_REAL_API" == "true" && -z "$OPENAI_API_KEY" ]]; then
    print_error "Real API testing requires OPENAI_API_KEY to be set"
    print_warning "Either set the environment variable or use --api-key option"
    exit 1
fi

# Set up environment
export USE_REAL_API
export OPENAI_API_KEY

# Print configuration
print_status "OpenAI Responses API Test Configuration:"
echo "  Real API: $USE_REAL_API"
if [[ "$USE_REAL_API" == "true" ]]; then
    echo "  API Key: ${OPENAI_API_KEY:0:8}..." # Show only first 8 chars
fi
if [[ -n "$TEST_FILTER" ]]; then
    echo "  Filter: $TEST_FILTER"
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

# Add filter if specified
if [[ -n "$TEST_FILTER" ]]; then
    TEST_CMD="$TEST_CMD --filter $TEST_FILTER"
fi

# Add specific test targets for Responses API
if [[ -n "$TEST_FILTER" ]]; then
    # If filter is specified, use it
    TEST_CMD="$TEST_CMD"
else
    # Run all Responses API tests
    TEST_CMD="$TEST_CMD --filter OpenAIResponses"
fi

# Run the tests
print_status "Running OpenAI Responses API tests..."
echo "Command: $TEST_CMD"
echo ""

if [[ "$VERBOSE" == "true" ]]; then
    eval $TEST_CMD
else
    eval $TEST_CMD 2>&1 | grep -E "(Test Case|✅|❌|PASS|FAIL|error:|warning:)"
fi

TEST_RESULT=$?

echo ""
if [[ $TEST_RESULT -eq 0 ]]; then
    print_success "All tests passed! 🎉"
    
    if [[ "$USE_REAL_API" == "true" ]]; then
        print_success "Real API integration tests completed successfully"
    else
        print_success "Mock tests completed successfully"
        print_warning "To test with real API, use: $0 --real-api"
    fi
else
    print_error "Some tests failed"
    exit 1
fi

# Additional information
echo ""
print_status "Test Categories Available:"
echo "  • OpenAIResponsesAPITests         - Core functionality"
echo "  • OpenAIResponsesStreamingTests   - Streaming features"
echo "  • OpenAIResponsesToolsTests       - Built-in tools"
echo "  • OpenAIResponsesRealAPITests     - Real API integration"
echo ""
print_status "To run specific categories:"
echo "  $0 --filter OpenAIResponsesAPITests"
echo "  $0 --filter OpenAIResponsesStreamingTests"
echo "  $0 --real-api --filter OpenAIResponsesRealAPITests" 