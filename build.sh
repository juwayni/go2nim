#!/usr/bin/env bash

# GONIM - Production-Ready Go to Nim Transpiler
# Build and Installation Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

echo "=== GONIM Build System ==="
echo "Build directory: $BUILD_DIR"
echo "Install directory: $INSTALL_DIR"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check dependencies
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed${NC}"
        echo "Please install $1 and try again"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} $1 found"
}

echo "Checking dependencies..."
check_dependency "go"
check_dependency "nim"
check_dependency "nimble"

GO_VERSION=$(go version | awk '{print $3}')
NIM_VERSION=$(nim --version | head -n1 | awk '{print $4}')
echo "Go version: $GO_VERSION"
echo "Nim version: $NIM_VERSION"
echo ""

# Create build directory
mkdir -p "$BUILD_DIR"

# Step 1: Build Go compiler frontend
echo -e "${YELLOW}=== Building Go Compiler Frontend ===${NC}"
cd "$SCRIPT_DIR/compiler"

echo "Installing Go dependencies..."
go mod init gonim-compiler 2>/dev/null || true
go get golang.org/x/tools/go/packages
go get golang.org/x/tools/go/ssa
go get golang.org/x/tools/go/ssa/ssautil

echo "Building compiler..."
go build -o "$BUILD_DIR/gonim-compile" main.go
echo -e "${GREEN}✓${NC} Go compiler frontend built successfully"
echo ""

# Step 2: Build Nim backend
echo -e "${YELLOW}=== Building Nim Backend ===${NC}"
echo "Compiling Nim backend..."
nim c -d:release --opt:speed -o:"$BUILD_DIR/gonim-backend" backend.nim
echo -e "${GREEN}✓${NC} Nim backend built successfully"
echo ""

# Step 3: Create wrapper script
echo -e "${YELLOW}=== Creating GONIM CLI ===${NC}"
cat > "$BUILD_DIR/gonim" << 'EOF'
#!/usr/bin/env bash

# GONIM - Go to Nim Transpiler CLI
VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPILE_BIN="$SCRIPT_DIR/gonim-compile"
BACKEND_BIN="$SCRIPT_DIR/gonim-backend"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_usage() {
    cat << USAGE
GONIM - Go to Nim Transpiler v$VERSION

Usage: gonim [options] <command> [arguments]

Commands:
    transpile <input>       Transpile Go package to Nim
    build <input>           Transpile and build executable
    run <input>             Transpile, build, and run
    version                 Show version information
    help                    Show this help message

Options:
    -o <dir>                Output directory (default: nim_output)
    -v                      Verbose output
    --keep-ir               Keep intermediate IR file
    --optimize              Enable optimizations
    
Examples:
    gonim transpile ./myapp
    gonim build -o build ./myapp
    gonim run ./examples/hello
    
For more information, visit: https://github.com/gonim/gonim
USAGE
}

show_version() {
    echo "GONIM v$VERSION"
    echo "Go to Nim Transpiler"
    echo ""
    go version
    nim --version | head -n1
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Parse options
OUTPUT_DIR="nim_output"
VERBOSE=""
KEEP_IR=""
OPTIMIZE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -o)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -v)
            VERBOSE="-v"
            shift
            ;;
        --keep-ir)
            KEEP_IR="true"
            shift
            ;;
        --optimize)
            OPTIMIZE="true"
            shift
            ;;
        transpile|build|run|version|help)
            COMMAND="$1"
            shift
            break
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

case "$COMMAND" in
    version)
        show_version
        exit 0
        ;;
    help|"")
        show_usage
        exit 0
        ;;
esac

INPUT_PATH="${1:-.}"

if [ ! -e "$INPUT_PATH" ]; then
    log_error "Input path does not exist: $INPUT_PATH"
    exit 1
fi

IR_FILE="$OUTPUT_DIR/ir.json"

transpile() {
    log_info "Transpiling Go package: $INPUT_PATH"
    
    # Step 1: Generate IR
    log_info "Generating intermediate representation..."
    if [ -n "$VERBOSE" ]; then
        "$COMPILE_BIN" -input="$INPUT_PATH" -output="$IR_FILE" -v
    else
        "$COMPILE_BIN" -input="$INPUT_PATH" -output="$IR_FILE"
    fi
    
    if [ $? -ne 0 ]; then
        log_error "Failed to generate IR"
        exit 1
    fi
    log_success "IR generated: $IR_FILE"
    
    # Step 2: Generate Nim code
    log_info "Generating Nim code..."
    "$BACKEND_BIN" -i "$IR_FILE" -o "$OUTPUT_DIR"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to generate Nim code"
        exit 1
    fi
    log_success "Nim code generated in: $OUTPUT_DIR"
    
    # Clean up IR if not keeping
    if [ -z "$KEEP_IR" ]; then
        rm -f "$IR_FILE"
    fi
}

build_nim() {
    log_info "Building Nim executable..."
    
    cd "$OUTPUT_DIR"
    
    NIM_FLAGS="-d:release"
    if [ -n "$OPTIMIZE" ]; then
        NIM_FLAGS="$NIM_FLAGS --opt:speed --passC:-O3"
    fi
    
    nim c $NIM_FLAGS main.nim
    
    if [ $? -ne 0 ]; then
        log_error "Failed to build Nim executable"
        exit 1
    fi
    
    log_success "Executable built: $OUTPUT_DIR/main"
}

case "$COMMAND" in
    transpile)
        transpile
        ;;
    build)
        transpile
        build_nim
        ;;
    run)
        transpile
        build_nim
        log_info "Running executable..."
        "$OUTPUT_DIR/main"
        ;;
esac
EOF

chmod +x "$BUILD_DIR/gonim"
echo -e "${GREEN}✓${NC} GONIM CLI created"
echo ""

# Step 4: Install (optional)
if [ "$1" == "install" ]; then
    echo -e "${YELLOW}=== Installing GONIM ===${NC}"
    mkdir -p "$INSTALL_DIR"
    cp "$BUILD_DIR/gonim" "$INSTALL_DIR/"
    cp "$BUILD_DIR/gonim-compile" "$INSTALL_DIR/"
    cp "$BUILD_DIR/gonim-backend" "$INSTALL_DIR/"
    echo -e "${GREEN}✓${NC} GONIM installed to $INSTALL_DIR"
    echo ""
    echo "Add $INSTALL_DIR to your PATH if not already present:"
    echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
fi

# Step 5: Run tests
echo -e "${YELLOW}=== Build Summary ===${NC}"
echo "Build directory: $BUILD_DIR"
echo ""
echo "Built components:"
echo "  • gonim-compile   (Go frontend)"
echo "  • gonim-backend   (Nim backend)"
echo "  • gonim           (CLI wrapper)"
echo ""
echo -e "${GREEN}Build completed successfully!${NC}"
echo ""
echo "To use GONIM:"
echo "  $BUILD_DIR/gonim transpile <go-package>"
echo ""
echo "To install system-wide:"
echo "  $0 install"
echo ""
echo "To run tests:"
echo "  $BUILD_DIR/gonim run examples/hello"
