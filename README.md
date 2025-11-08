# BoringCache Ruby

Prebuilt Ruby distributions with multiple variants for fast CI/CD setup. Built with `ruby-build` and cached using BoringCache for instant Ruby environment provisioning.

## Quick Start

```bash
# Install BoringCache CLI
curl -sSL https://install.boringcache.com/install.sh | sh

# Restore Ruby (standard variant)
boringcache restore ruby/ruby ruby-3.3.8-macos-15-arm64 ./ruby

# Add to PATH and use
export PATH="$PWD/ruby/ruby/bin:$PATH"
ruby --version
```

## Choosing a Workspace

Ruby artifacts are published to the `ruby/ruby` workspace by default. Set `BORINGCACHE_DEFAULT_WORKSPACE`
to point the CLI and build scripts at a different workspace:

```bash
# Use a custom workspace everywhere (recommended for CI)
export BORINGCACHE_DEFAULT_WORKSPACE="acme/ruby"
# Or only override a single command
BORINGCACHE_DEFAULT_WORKSPACE="acme/ruby" make upload
```

## Supported Platforms & Architectures

| Platform | Architectures | Runner | Notes |
|----------|---------------|--------|-------|
| **Ubuntu 22.04** | amd64, arm64 | Native GitHub Actions | Full variant support |
| **Ubuntu 24.04** | amd64, arm64 | Native GitHub Actions | Full variant support |
| **Debian Bookworm** | amd64, arm64 | Docker on GitHub Actions | Full variant support |
| **Debian Bullseye** | amd64, arm64 | Docker on GitHub Actions | Full variant support |
| **Alpine Linux** | amd64 | Docker on GitHub Actions | pthread coroutines |
| **Arch Linux** | amd64 | Docker on GitHub Actions | Full variant support |
| **macOS** | amd64 (macOS 13), arm64 (macOS 15) | Native GitHub Actions | Full variant support |
| **Windows** | amd64 (2022), arm64 (11-arm) | Native GitHub Actions | Standard variant only, Ruby 3.4.x only |

## Ruby Variants

Each platform builds multiple Ruby variants optimized for different use cases:

### 1. Standard (Default)
```bash
# Tag format: ruby-VERSION-PLATFORM-ARCH
boringcache restore ruby/ruby ruby-3.3.8-ubuntu-22-04-amd64 ./ruby
```

**Features:**
- Standard Ruby interpreter
- All default features enabled
- Maximum compatibility
- Shared library support

**Configure options:** `--without-jemalloc --disable-yjit`

### 2. YJIT (JIT Compiler)
```bash
# Tag format: ruby-VERSION-yjit-PLATFORM-ARCH  
boringcache restore ruby/ruby ruby-3.3.8-yjit-ubuntu-22-04-amd64 ./ruby
```

**Features:**
- Yet Another Ruby JIT compiler
- Improved runtime performance
- Requires Rust 1.58+
- Not available on Windows

**Configure options:** `--enable-yjit --without-jemalloc`

### 3. Jemalloc (Memory Allocator)
```bash
# Tag format: ruby-VERSION-jemalloc-PLATFORM-ARCH
boringcache restore ruby/ruby ruby-3.3.8-jemalloc-ubuntu-22-04-amd64 ./ruby
```

**Features:**
- jemalloc memory allocator
- Better memory management
- Reduced fragmentation
- Not available on Windows

**Configure options:** `--with-jemalloc --disable-yjit`

## Variant Availability by Platform

| Platform | Standard | YJIT | Jemalloc | Notes |
|----------|----------|------|----------|-------|
| **Linux (Ubuntu/Debian)** | ✅ | ✅ | ✅ | Full support |
| **Alpine Linux** | ✅ | ✅ | ✅ | pthread coroutines |
| **macOS** | ✅ | ✅ | ✅ | via Homebrew |
| **Windows** | ✅ | ❌ | ❌ | POSIX limitations |
| **Arch Linux** | ✅ | ✅ | ✅ | Full support |

## Ruby Versions

We build only **officially supported** Ruby versions (3 latest from each non-EOL series):

### Ruby 3.5.x (Preview)
- `3.5.0-preview1` - Preview/development version with latest features

### Ruby 3.4.x (Current Stable)
- `3.4.6` (high priority) - Normal maintenance until Dec 2024, then security maintenance until Dec 2027
- `3.4.5` (medium priority)
- `3.4.4` (low priority)

### Ruby 3.3.x (Stable) 
- `3.3.9` (high priority) - Normal maintenance until Mar 2027
- `3.3.8` (medium priority) - Available on Linux/macOS (Windows not supported)

**Note**: Ruby 3.1.x reached end-of-life (EOL) on March 26, 2025 and is no longer supported.

## Usage Examples

### GitHub Actions

```yaml
name: CI with BoringCache Ruby
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    env:
      BORINGCACHE_API_TOKEN: ${{ secrets.BORINGCACHE_API_TOKEN }}
    
    steps:
      - uses: actions/checkout@v4
      
      # Install BoringCache CLI
      - name: Install BoringCache CLI
        run: curl -sSL https://install.boringcache.com/install.sh | sh
      
      # Restore prebuilt Ruby with YJIT
      - name: Setup Ruby
        run: |
          boringcache restore ruby/ruby ruby-3.3.8-yjit-ubuntu-22-04-amd64 ./ruby
          echo "$PWD/ruby/ruby/bin" >> $GITHUB_PATH
      
      - name: Ruby info
        run: |
          ruby --version
          ruby -e "puts RubyVM::YJIT.enabled? ? 'YJIT: ON' : 'YJIT: OFF'"
      
      - name: Install dependencies
        run: |
          gem install bundler
          bundle install
      
      - name: Run tests
        run: bundle exec rake test
```

### Docker

```dockerfile
FROM ubuntu:22.04

# Install BoringCache CLI
RUN curl -sSL https://install.boringcache.com/install.sh | sh

# Restore Ruby (requires BORINGCACHE_API_TOKEN)
RUN boringcache restore ruby/ruby ruby-3.3.8-ubuntu-22-04-amd64 /usr/local
ENV PATH="/usr/local/ruby/bin:$PATH"

# Your application
COPY . /app
WORKDIR /app
RUN bundle install
CMD ["ruby", "app.rb"]
```

### Local Development

```bash
# Install BoringCache CLI
curl -sSL https://install.boringcache.com/install.sh | sh

# Restore specific Ruby variant
boringcache restore ruby/ruby ruby-3.3.8-jemalloc-macos-15-arm64 ~/ruby-jemalloc

# Use this Ruby
export PATH="$HOME/ruby-jemalloc/ruby/bin:$PATH"
ruby --version

# Install gems
gem install rails
```

## Software Bill of Materials (SBOM)

Each Ruby build includes a comprehensive SBOM in CycloneDX format that provides:

### SBOM Contents
- **Ruby core component** with version and variant information
- **Bundled gems** (minitest, bundler, rake, etc.) with versions
- **Build tools** (ruby-build, BoringCache CLI) with versions
- **Platform properties** (architecture, OS, variant features)

### SBOM Example
```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "metadata": {
    "component": {
      "name": "ruby-yjit",
      "version": "3.3.8",
      "description": "Ruby 3.3.8 (yjit variant) for ubuntu-22-04-amd64"
    }
  },
  "components": [
    {
      "type": "application",
      "name": "ruby",
      "version": "3.3.8",
      "properties": [
        { "name": "ruby:variant", "value": "yjit" },
        { "name": "ruby:yjit_enabled", "value": "yes" },
        { "name": "ruby:jemalloc_enabled", "value": "false" },
        { "name": "ruby:platform", "value": "ubuntu-22.04" },
        { "name": "ruby:architecture", "value": "amd64" }
      ]
    }
  ]
}
```

### SBOM Features
- **Automatic detection** by BoringCache CLI
- **Security scanning** capability
- **Compliance auditing** support
- **Dependency tracking** for bundled gems

## Performance Benefits

- **Fast setup**: 10-30 seconds vs 2-5 minutes for source builds
- **Consistent environment**: Identical Ruby across all builds
- **Optimized binaries**: Built with performance optimizations
- **Shared library support**: Dynamic linking when beneficial
- **Automatic compression**: BoringCache handles optimal compression

## Local Building

### Build Single Variant
```bash
# Build standard Ruby
make build RUBY_VERSION=3.3.8 PLATFORM=ubuntu-22.04 ARCH=amd64

# Build specific variant
make build RUBY_VERSION=3.3.8 PLATFORM=macos ARCH=arm64 VARIANTS=yjit
```

### Build All Variants
```bash
# All variants for current platform
make ci-build RUBY_VERSION=3.3.8

# Cross-platform build (if supported)
make ci-build RUBY_VERSION=3.3.8 PLATFORM=alpine ARCH=amd64
```

### Platform-Specific Requirements

#### macOS
```bash
# Install dependencies via Homebrew
brew install openssl@3 readline libyaml gdbm libffi autoconf bison rust
brew install jemalloc  # For jemalloc variant
```

#### Ubuntu/Debian  
```bash
# Install build dependencies
sudo apt-get install build-essential libssl-dev libreadline-dev \
  zlib1g-dev libffi-dev libyaml-dev libgdbm-dev autoconf bison rustc
sudo apt-get install libjemalloc-dev  # For jemalloc variant
```

#### Alpine
```bash
# Install dependencies
apk add build-base openssl-dev readline-dev zlib-dev libffi-dev \
  yaml-dev gdbm-dev autoconf bison rust
apk add jemalloc-dev  # For jemalloc variant
```

## Configuration Files

### versions.yml
Defines Ruby versions and platform configurations:
```yaml
versions:
  - version: "3.3.8"
    status: "stable"
    priority: "high"

platforms:
  ubuntu-22.04:
    architectures: ["amd64", "arm64"]
    runners:
      amd64: "ubuntu-22.04"
      arm64: "ubuntu-22.04-arm"
    build_type: "native"
```

### Makefile Targets
```bash
make help           # Show available targets
make build          # Build Ruby locally  
make ci-build       # Build and upload to cache
make clean          # Clean build artifacts
make info           # Show build configuration
```

## Cache Tag Format

Tags follow a consistent pattern for easy discovery:

### Standard Variant
```
ruby-{VERSION}-{PLATFORM}-{ARCH}
```
Examples:
- `ruby-3.3.8-ubuntu-22-04-amd64`
- `ruby-3.3.8-macos-15-arm64`
- `ruby-3.3.8-windows-2022-amd64`

### Other Variants
```
ruby-{VERSION}-{VARIANT}-{PLATFORM}-{ARCH}
```
Examples:
- `ruby-3.3.8-yjit-ubuntu-22-04-amd64`
- `ruby-3.3.8-jemalloc-macos-13-amd64`

## Environment Variables

### Required for CI
```bash
export BORINGCACHE_API_TOKEN="your-token"
export BORINGCACHE_API_URL="https://api.boringcache.com"  # Optional
```

### Build Configuration
```bash
export RUBY_VERSION="3.3.8"       # Ruby version to build
export PLATFORM="ubuntu-22.04"     # Target platform
export ARCH="amd64"                # Target architecture  
export VARIANTS="standard,yjit"    # Variants to build
```

## Architecture

### Build Process
1. **GitHub Actions** triggers on version updates or manual dispatch
2. **Matrix strategy** builds across all platform/architecture combinations
3. **ruby-build** compiles Ruby from source with variant-specific options
4. **SBOM generation** creates software bill of materials
5. **BoringCache upload** saves with automatic SBOM detection

### Variant Selection
The build system automatically selects appropriate variants per platform:
- **Windows**: Only standard (YJIT/jemalloc unsupported)
- **Linux/macOS**: All variants (standard, yjit, jemalloc)
- **Alpine**: All variants with pthread coroutines

### Quality Assurance
- **Build verification** tests Ruby installation
- **Shared library checks** ensures dynamic linking works
- **SBOM validation** verifies complete dependency capture
- **Platform testing** across all supported architectures

## Troubleshooting

### Common Issues

#### Ruby not found after restore
```bash
# Check if restore worked
ls -la ./ruby/ruby/bin/ruby

# Add to PATH
export PATH="$PWD/ruby/ruby/bin:$PATH"
```

#### Shared library errors
```bash
# Set library path (Linux)
export LD_LIBRARY_PATH="$PWD/ruby/ruby/lib:$LD_LIBRARY_PATH"

# Set library path (macOS)  
export DYLD_LIBRARY_PATH="$PWD/ruby/ruby/lib:$DYLD_LIBRARY_PATH"
```

#### Platform-specific variants unavailable
```bash
# Check variant availability for your platform
boringcache ls ruby/ruby | grep ruby-3.3.8 | grep $(uname -m)

# Use standard variant if others unavailable
boringcache restore ruby/ruby ruby-3.3.8-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m) ./ruby
```

#### Windows limitations
Windows builds only support the standard Ruby variant:

```bash
# Windows - only standard variant available
boringcache restore ruby/ruby ruby-3.3.8-windows-2022-amd64 ./ruby

# For YJIT/jemalloc on Windows, use WSL2 or Docker
wsl
boringcache restore ruby/ruby ruby-3.3.8-yjit-ubuntu-22-04-amd64 ./ruby
```

## Contributing

### Adding New Ruby Versions
1. Update `versions.yml` with new version information
2. GitHub Actions will automatically build and upload
3. Test with your applications

### Platform Support
New platforms can be added by:
1. Adding platform configuration to `versions.yml`
2. Adding platform-specific build logic to `scripts/build-ruby-variants.sh`  
3. Testing across all variants

## License

MIT License - see LICENSE file for details.
