#!/bin/bash
# test/cpp/build_and_test.sh

# Exit immediately if a command exits with a non-zero status
set -e

readonly BASE_DIR=$(dirname "$(readlink -f "$0")")
readonly LIB_DIR=$(realpath "${BASE_DIR}/../../lib/geometry")
readonly BUILD_DIR="${LIB_DIR}/build"

# Using a more descriptive array name
readonly REQUIRED_FILES=(
    "$LIB_DIR/bezier.hpp"
    "$LIB_DIR/bezier.cpp"
    "$LIB_DIR/CMakeLists.txt"
    "$BASE_DIR/test_bezier.cpp"
)

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "[INFO] Running $(basename "$0") - $(date +%F)"

# 1. Cleanup: Remove existing build directory if it exists
if [[ -d "$BUILD_DIR" ]]; then
    echo "[CLEAN] Removing existing build directory..."
    rm -rf "$BUILD_DIR"
fi

# 2. Dependency Check
for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo -e "[CHECK] $file ... ${GREEN}OK${NC}"
    else
        echo -e "[ERROR] $file not found!"
        exit 1
    fi
done

# 3. Build Process
cd "$LIB_DIR"

echo "[BUILD] Configuring CMake..."
cmake -B build -S . -DDRAFTSTEP_BUILD_TESTS=ON

echo "[BUILD] Compiling..."
cmake --build build --parallel $(nproc)

# 4. Execution
echo "[TEST] Running CTest suite..."
ctest --test-dir build --output-on-failure

# 5. Manual execution check (Optional if CTest is configured correctly)
if [[ -f "$BUILD_DIR/test_bezier" ]]; then
    echo "[RUN] Executing standalone test binary..."
    "$BUILD_DIR/test_bezier"
else
    echo -e "${RED}[FAIL] Executable 'test_bezier' not found!${NC}"
    exit 1
fi

echo -e "${GREEN}[SUCCESS] All tests passed.${NC}"
