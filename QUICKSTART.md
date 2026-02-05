# GONIM Quick Start Guide

## Installation (5 minutes)

### Prerequisites
```bash
# Install Go 1.21+
curl -OL https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Install Nim 2.0+
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
export PATH=$PATH:$HOME/.nimble/bin
```

### Build GONIM
```bash
cd gonim
./build.sh
./build.sh install  # Optional: system-wide install
```

## Usage (30 seconds)

### Transpile Your First Go Program
```bash
# Create a simple Go program
cat > hello.go << 'GOCODE'
package main

import (
    "fmt"
    "time"
)

func main() {
    fmt.Println("Hello from GONIM!")
    
    ch := make(chan string, 1)
    go func() {
        time.Sleep(100 * time.Millisecond)
        ch <- "Goroutine says hi!"
    }()
    
    msg := <-ch
    fmt.Println(msg)
}
GOCODE

# Transpile and run
gonim run hello.go
```

**Expected Output:**
```
Hello from GONIM!
Goroutine says hi!
```

## Examples Included

### 1. Basic Example (tests/example.go)
```bash
gonim run tests/example.go
```
Tests: print, goroutines, channels, WaitGroup, defer, structs

### 2. Comprehensive Tests (tests/comprehensive.go)
```bash
gonim run tests/comprehensive.go
```
Tests: All major Go features including complex workflows

### 3. Advanced Patterns (tests/advanced.go)
```bash
gonim run tests/advanced.go
```
Tests: Generics, worker pools, pub/sub, context patterns

## Common Commands

```bash
# Transpile only
gonim transpile ./myapp

# Transpile and build
gonim build ./myapp -o build

# Run immediately
gonim run ./myapp

# With optimization
gonim build --optimize ./myapp

# Keep IR for debugging
gonim build --keep-ir ./myapp

# Verbose output
gonim build -v ./myapp
```

## Supported Features ✓

- ✅ Goroutines (spawn threads)
- ✅ Channels (buffered/unbuffered)
- ✅ Defer statements
- ✅ Interfaces & methods
- ✅ Structs & types
- ✅ Slices & maps
- ✅ Sync primitives (Mutex, WaitGroup, etc.)
- ✅ Standard library (fmt, io, time, sync, strings, os, http)
- ✅ CGO integration
- ✅ Error handling
- ✅ Multiple packages

## Project Structure

```
your-go-project/
├── main.go
├── package1/
│   └── code.go
└── package2/
    └── code.go

# Transpile entire project
gonim build .

# Output
nim_output/
├── main.nim
├── runtime.nim
└── (generated code)
```

## Troubleshooting

**"gonim: command not found"**
```bash
export PATH=$PATH:$(pwd)/build
# or use: ./build/gonim
```

**"Package not found"**
```bash
cd your-go-project
go mod init myproject
go mod tidy
gonim transpile .
```

**Build fails**
```bash
# Check dependencies
nim --version  # Should be 2.0+
go version     # Should be 1.21+

# Try verbose mode
gonim build -v ./myapp
```

## Next Steps

1. **Read README.md** - Full documentation
2. **Check ARCHITECTURE.md** - Technical details
3. **Explore stdlib/** - Available Go packages
4. **Run tests/** - See what works
5. **Build your app** - Start transpiling!

## Support

- Issues: https://github.com/gonim/gonim/issues
- Docs: https://gonim.dev
- Email: support@gonim.dev

**Happy Transpiling! 🚀**
