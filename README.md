# BoringCache Ruby

Prebuilt Ruby distributions with multiple variants for fast CI/CD setup. Built with `ruby-build` and cached using BoringCache.

## Quick Start

```bash
# Install BoringCache CLI
curl -sSL https://install.boringcache.com/install.sh | sh

# Restore Ruby
boringcache restore ruby/ruby ruby-3.4.8-macos-15-arm64 ./ruby

# Add to PATH
export PATH="$PWD/ruby/ruby/bin:$PATH"
ruby --version
```

### Usage with mise

```bash
# Restore into mise's install directory
VERSION=3.4.8
boringcache restore ruby/ruby ruby-${VERSION}-yjit-macos-15-arm64 \
  ~/.local/share/mise/installs/ruby/${VERSION}

# Tell mise it's installed
mise use ruby@${VERSION}
ruby --version
```

### Usage with rbenv

```bash
# Restore into rbenv's versions directory
VERSION=3.4.8
boringcache restore ruby/ruby ruby-${VERSION}-yjit-ubuntu-22-04-amd64 \
  ~/.rbenv/versions/${VERSION}

# Rebuild shims and set version
rbenv rehash
rbenv shell ${VERSION}
ruby --version
gem env home
# => ~/.rbenv/versions/3.4.8/lib/ruby/gems/...
```

## Supported Versions

| Series | Versions | Status | EOL |
|--------|----------|--------|-----|
| **4.0** | 4.0.1, 4.0.0 | Stable | Mar 2029 |
| **3.4** | 3.4.8, 3.4.7, 3.4.6 | Stable | Mar 2028 |
| **3.3** | 3.3.10, 3.3.9, 3.3.8 | Stable | Mar 2027 |
| **3.2** | 3.2.10, 3.2.9, 3.2.8 | Security | Mar 2026 |

## Supported Platforms

| Platform | Architectures | Variants | EOL |
|----------|---------------|----------|-----|
| Ubuntu 22.04 | amd64, arm64 | all | Apr 2027 |
| Ubuntu 24.04 | amd64, arm64 | all | Apr 2029 |
| Ubuntu 25.04 | amd64, arm64 | all | Jan 2026 |
| Debian Bookworm | amd64, arm64 | all | Jun 2028 |
| Alpine Linux | amd64 | all | Rolling |
| Arch Linux | amd64 | all | Rolling |
| macOS 15 | arm64 | all | - |
| Windows | amd64, arm64 | standard only | - |

## Variants

| Variant | Description | Configure Options |
|---------|-------------|-------------------|
| **standard** | Default Ruby | `--disable-yjit --without-jemalloc` |
| **yjit** | With YJIT JIT compiler | `--enable-yjit --without-jemalloc` |
| **jemalloc** | With jemalloc allocator | `--disable-yjit --with-jemalloc` |
| **jemalloc-yjit** | Both YJIT and jemalloc | `--enable-yjit --with-jemalloc` |

## Cache Tag Format

```
# Standard variant
ruby-{VERSION}-{PLATFORM}-{ARCH}

# Other variants
ruby-{VERSION}-{VARIANT}-{PLATFORM}-{ARCH}
```

Examples:
- `ruby-3.4.8-ubuntu-22-04-amd64`
- `ruby-3.4.8-yjit-macos-15-arm64`
- `ruby-3.4.8-jemalloc-debian-bookworm-arm64`

## GitHub Actions Example

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
          boringcache restore ruby/ruby ruby-3.4.8-yjit-ubuntu-22-04-amd64 ./ruby
          echo "$PWD/ruby/ruby/bin" >> $GITHUB_PATH

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
export LD_LIBRARY_PATH="$PWD/ruby/ruby/lib:$LD_LIBRARY_PATH"

# Shared library errors on macOS
export DYLD_LIBRARY_PATH="$PWD/ruby/ruby/lib:$DYLD_LIBRARY_PATH"
```

## License

MIT
