# BoringCache Ruby

Prebuilt Ruby distributions with multiple variants for fast CI/CD setup. Built with `ruby-build` and cached using BoringCache.

## Quick Start

```bash
# Install BoringCache CLI
curl -sSL https://install.boringcache.com/install.sh | sh

# Restore Ruby
boringcache restore ruby/ruby ruby-3.4.7-macos-15-arm64 ./ruby

# Add to PATH
export PATH="$PWD/ruby/ruby/bin:$PATH"
ruby --version
```

## Supported Versions

| Series | Version | Status | EOL |
|--------|---------|--------|-----|
| **4.0** | 4.0.0-preview2 | Preview | TBD |
| **3.5** | 3.5.0-preview1 | Preview | TBD |
| **3.4** | 3.4.7 | Stable | Mar 2028 |
| **3.3** | 3.3.10 | Stable | Mar 2027 |
| **3.2** | 3.2.8 | Security | Mar 2026 |

## Supported Platforms

| Platform | Architectures | Variants | EOL |
|----------|---------------|----------|-----|
| Ubuntu 20.04 | amd64, arm64 | standard, yjit, jemalloc, jemalloc-yjit | Apr 2025 |
| Ubuntu 22.04 | amd64, arm64 | standard, yjit, jemalloc, jemalloc-yjit | Apr 2027 |
| Ubuntu 24.04 | amd64, arm64 | standard, yjit, jemalloc, jemalloc-yjit | Apr 2029 |
| Debian Bookworm | amd64, arm64 | standard, yjit, jemalloc, jemalloc-yjit | Jun 2028 |
| Alpine Linux | amd64 | standard, yjit, jemalloc, jemalloc-yjit | Rolling |
| Arch Linux | amd64 | standard, yjit, jemalloc, jemalloc-yjit | Rolling |
| macOS 15 | arm64 | standard, yjit, jemalloc, jemalloc-yjit | - |
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
- `ruby-3.4.7-ubuntu-22-04-amd64`
- `ruby-3.4.7-yjit-macos-15-arm64`
- `ruby-3.4.7-jemalloc-debian-bookworm-arm64`

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
          boringcache restore ruby/ruby ruby-3.4.7-yjit-ubuntu-22-04-amd64 ./ruby
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
make build RUBY_VERSION=3.4.7 PLATFORM=ubuntu-22.04 ARCH=amd64 VARIANTS=yjit

# Build and upload
make ci-build RUBY_VERSION=3.4.7 PLATFORM=ubuntu-22.04 ARCH=amd64
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `BORINGCACHE_API_TOKEN` | API token (required) |
| `BORINGCACHE_API_URL` | API URL (optional) |
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
