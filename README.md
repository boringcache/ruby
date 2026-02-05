# BoringCache Ruby

Prebuilt Ruby distributions with multiple variants for fast CI/CD setup. Built with `ruby-build` and cached using BoringCache.

**Seconds** to install Ruby instead of 5-15 minutes compiling from source. Archives are ~12-17 MB compressed.

## Quick Start

```bash
# Install BoringCache CLI
curl -sSL https://install.boringcache.com/install.sh | sh

# Restore Ruby (tag:path format)
boringcache restore ruby/ruby ruby-3.4.8-yjit-macos-15-arm64:/tmp/bc-ruby

# Add to PATH
export PATH="/tmp/bc-ruby/bin:$PATH"
ruby --version
```

### Usage with mise

```bash
VERSION=3.4.8
INSTALL_DIR=~/.local/share/mise/installs/ruby/${VERSION}
mkdir -p "${INSTALL_DIR}"

# Restore and move into mise's install directory
boringcache restore ruby/ruby ruby-${VERSION}-yjit-macos-15-arm64:/tmp/bc-ruby
mv /tmp/bc-ruby/* "${INSTALL_DIR}/" && rm -rf /tmp/bc-ruby

# Tell mise it's installed
mise use ruby@${VERSION}
ruby --version
```

### Usage with rbenv

```bash
VERSION=3.4.8
INSTALL_DIR=~/.rbenv/versions/${VERSION}
mkdir -p "${INSTALL_DIR}"

# Restore and move into rbenv's versions directory
boringcache restore ruby/ruby ruby-${VERSION}-yjit-ubuntu-22-04-amd64:/tmp/bc-ruby
mv /tmp/bc-ruby/* "${INSTALL_DIR}/" && rm -rf /tmp/bc-ruby

# Rebuild shims and set version
rbenv rehash
rbenv shell ${VERSION}
ruby --version
```

## Variants

All versions are built in 4 variants (Windows: standard only):

| Variant | Tag example | Use case |
|---------|-------------|----------|
| **standard** | `ruby-3.4.8-ubuntu-22-04-amd64` | Default, maximum compatibility |
| **yjit** | `ruby-3.4.8-yjit-macos-15-arm64` | Best runtime performance |
| **jemalloc** | `ruby-3.4.8-jemalloc-debian-bookworm-arm64` | Reduced memory fragmentation |
| **jemalloc-yjit** | `ruby-3.4.8-jemalloc-yjit-ubuntu-24-arm64` | Best performance + memory |

Native extensions (nokogiri, nio4r, etc.) compile normally against all variants.

## Supported Versions

| Series | Versions | Status | EOL |
|--------|----------|--------|-----|
| **4.0** | 4.0.1, 4.0.0 | Stable | Mar 2029 |
| **3.4** | 3.4.8, 3.4.7, 3.4.6 | Stable | Mar 2028 |
| **3.3** | 3.3.10, 3.3.9, 3.3.8 | Stable | Mar 2027 |
| **3.2** | 3.2.10, 3.2.9, 3.2.8 | Security | Mar 2026 |

## Supported Platforms

| Platform | Architectures |
|----------|---------------|
| Ubuntu 22.04 | amd64, arm64 |
| Ubuntu 24.04 | amd64, arm64 |
| Ubuntu 25.04 | amd64, arm64 |
| Debian Bookworm | amd64, arm64 |
| Alpine Linux | amd64 |
| Arch Linux | amd64 |
| macOS 15 | arm64 |
| Windows | amd64, arm64 |

## Cache Tag Format

```
ruby-{VERSION}[-{VARIANT}]-{PLATFORM}-{ARCH}
```

## GitHub Actions

```yaml
name: CI
on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    env:
      BORINGCACHE_API_TOKEN: ${{ secrets.BORINGCACHE_API_TOKEN }}
    steps:
      - uses: actions/checkout@v4

      - name: Setup Ruby
        run: |
          curl -sSL https://install.boringcache.com/install.sh | sh
          boringcache restore ruby/ruby ruby-3.4.8-yjit-ubuntu-22-04-amd64:./ruby
          echo "$PWD/ruby/bin" >> $GITHUB_PATH

      - name: Test
        run: |
          ruby --version
          bundle install
          bundle exec rake test
```

## Local Building

```bash
# Build specific variant
make build RUBY_VERSION=3.4.8 PLATFORM=ubuntu-22.04 ARCH=amd64 VARIANTS=yjit

# Build and upload
make ci-build RUBY_VERSION=3.4.8 PLATFORM=ubuntu-22.04 ARCH=amd64
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `BORINGCACHE_API_TOKEN` | API token (required) |
| `BORINGCACHE_DEFAULT_WORKSPACE` | Workspace override (default: `ruby/ruby`) |

## Troubleshooting

```bash
# Shared library errors on Linux
export LD_LIBRARY_PATH="$PWD/ruby/lib:$LD_LIBRARY_PATH"

# Shared library errors on macOS
export DYLD_LIBRARY_PATH="$PWD/ruby/lib:$DYLD_LIBRARY_PATH"
```

## License

MIT
