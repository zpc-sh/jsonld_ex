#!/bin/bash

# Test script to debug the release-full command issue

set -e

echo "Testing release-full command components..."

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get current version
CURRENT_VERSION=$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/')
echo -e "${GREEN}Current version:${NC} $CURRENT_VERSION"

echo ""
echo -e "${BLUE}Release type:${NC}"
echo "  1. Patch ($CURRENT_VERSION -> $(echo $CURRENT_VERSION | awk -F. '{print $1"."$2"."($3+1)}'))"
echo "  2. Minor ($CURRENT_VERSION -> $(echo $CURRENT_VERSION | awk -F. '{print $1"."($2+1)".0"}'))"
echo "  3. Major ($CURRENT_VERSION -> $(echo $CURRENT_VERSION | awk -F. '{print ($1+1)".0.0"}'))"
echo "  4. Custom version"
echo "  5. Skip version bump"

echo "Testing case statement with input '5':"
RELEASE_TYPE="5"
case $RELEASE_TYPE in
    1) echo "Patch selected" ;;
    2) echo "Minor selected" ;;
    3) echo "Major selected" ;;
    4) echo "Custom version selected" ;;
    5) echo "Skip version bump selected" ;;
    *) echo "Invalid choice: '$RELEASE_TYPE'"; exit 1 ;;
esac

echo ""
echo "Testing with different inputs:"
for test_input in "1" "2" "3" "4" "5" "invalid"; do
    case $test_input in
        1) echo "Input '$test_input': Patch" ;;
        2) echo "Input '$test_input': Minor" ;;
        3) echo "Input '$test_input': Major" ;;
        4) echo "Input '$test_input': Custom" ;;
        5) echo "Input '$test_input': Skip" ;;
        *) echo "Input '$test_input': Invalid" ;;
    esac
done

echo ""
echo "Testing variable expansion:"
echo "RELEASE_TYPE='5'"
RELEASE_TYPE="5"
echo "Value: '$RELEASE_TYPE'"
echo "Case result:"
case $RELEASE_TYPE in
    5) echo "  SUCCESS: Case 5 matched" ;;
    *) echo "  ERROR: Case 5 did not match" ;;
esac

echo ""
echo "All tests completed successfully!"