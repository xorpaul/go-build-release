# Go Build & Release Script

A comprehensive bash script for building Go applications for multiple platforms and automatically creating releases on GitHub or Gitea.

## Overview

This script automates the process of:
- Running tests
- Cross-compiling Go binaries for multiple platforms
- Compressing binaries with UPX (optional)
- Creating Git tags
- Creating releases on GitHub or Gitea
- Uploading binaries as release assets

## Features

- **Multi-platform builds**: Linux AMD64, macOS AMD64, macOS ARM64, Windows AMD64
- **Configurable builds**: Control which platforms to build via `.build.cfg` file
- **Automatic compression**: Uses UPX compression when available
- **Git integration**: Auto-creates tags and pushes to remote
- **Dual platform support**: Works with both GitHub and Gitea repositories
- **Auto-detection**: Automatically detects repository details from git remote

## Requirements

### System Requirements
- **Go**: Go programming language installed and configured
- **Git**: Git version control system
- **Bash**: Bash shell (Linux/macOS/WSL)

### Optional Dependencies
- **UPX**: Binary packer for compression (recommended)
  ```bash
  # Ubuntu/Debian
  sudo apt install upx-ucl
  
  # macOS
  brew install upx
  
  # Arch Linux
  sudo pacman -S upx
  ```

### GitHub Requirements
- **GitHub CLI (`gh`)**: Required for GitHub releases
  ```bash
  # Install via snap (as mentioned)
  sudo snap install gh
  
  # Or via package manager
  # Ubuntu/Debian
  sudo apt install gh
  
  # macOS
  brew install gh
  
  # Arch Linux
  sudo pacman -S github-cli
  ```
- **Authentication**: Must be logged in with `gh auth login`

### Gitea Requirements
- **curl**: HTTP client (usually pre-installed)
- **jq**: JSON processor for API responses
  ```bash
  # Ubuntu/Debian
  sudo apt install jq
  
  # macOS
  brew install jq
  
  # Arch Linux
  sudo pacman -S jq
  ```
- **Gitea configuration file**: `~/.gitea_env` with the following variables:
  ```bash
  GIT_TOKEN="your_gitea_api_token"
  GIT_URL="https://your-gitea-instance.com"
  ```

## Usage

### Basic Usage
```bash
./build_release.sh <version>
```

Examples:
```bash
./build_release.sh 1.0.0    # Creates tag v1.0.0
./build_release.sh v2.1.3   # Creates tag v2.1.3 (v prefix optional)
```

### Build Configuration

Create a `.build.cfg` file in your project root to control which platforms to build:

```bash
# .build.cfg example
BUILD_LINUX=true
BUILD_MACOS_AMD64=false
BUILD_MACOS_ARM64=true
BUILD_WINDOWS=true
```

If no `.build.cfg` file exists, all platforms are built by default.

### Available Configuration Options
- `BUILD_LINUX`: Linux AMD64 builds
- `BUILD_MACOS_AMD64`: macOS Intel builds
- `BUILD_MACOS_ARM64`: macOS Apple Silicon builds  
- `BUILD_WINDOWS`: Windows AMD64 builds

## How It Works

1. **Testing**: Runs `go test -v ./...` to ensure code quality
2. **Platform Detection**: Auto-detects repository details from git remote
3. **Build Configuration**: Reads `.build.cfg` or uses defaults
4. **Cross Compilation**: Builds binaries for specified platforms with:
   - Static linking (`CGO_ENABLED=0`)
   - Build time and version embedding
   - Binary stripping (`-s -w`)
5. **Compression**: Applies UPX compression if available
6. **Git Operations**: Creates and pushes git tags
7. **Release Creation**: 
   - GitHub repositories: Uses GitHub CLI to create releases
   - Gitea repositories: Uses API calls to create releases
8. **Asset Upload**: Uploads all built binaries as release assets

## Output Structure

Built binaries are placed in the `build/` directory with naming convention:
```
build/
├── projectname_v1.0.0_linux-amd64
├── projectname_v1.0.0_macos-amd64  
├── projectname_v1.0.0_macos-arm64
└── projectname_v1.0.0_windows-amd64.exe
```

## Environment Variables

The script automatically injects build metadata:
- `main.buildtime`: Build timestamp (UTC)
- `main.buildversion`: Release version

Access these in your Go code:
```go
var (
    buildtime    string
    buildversion string
)

func main() {
    fmt.Printf("Version: %s, Built: %s\n", buildversion, buildtime)
}
```

## Error Handling

The script includes comprehensive error handling:
- Validates version parameter
- Checks for required tools
- Verifies authentication status
- Handles existing releases gracefully
- Exits on build failures

## Platform Support

| Platform | Architecture | Status | Notes |
|----------|-------------|--------|-------|
| Linux | AMD64 | ✅ | UPX compression supported |
| macOS | AMD64 | ✅ | Intel Macs |
| macOS | ARM64 | ✅ | Apple Silicon Macs |
| Windows | AMD64 | ✅ | UPX compression supported |

## Troubleshooting

### Common Issues

**GitHub CLI not authenticated:**
```bash
gh auth login
```

**Missing UPX (non-critical):**
```bash
sudo apt install upx-ucl  # Ubuntu/Debian
```

**Gitea authentication:**
- Create `~/.gitea_env` with proper `GIT_TOKEN` and `GIT_URL`
- Ensure token has repository and release permissions

**Build failures:**
- Ensure Go modules are properly initialized
- Check that tests pass before building
- Verify cross-compilation dependencies

## License

This script is designed to work with any Go project and can be adapted to specific needs.