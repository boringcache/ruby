# BoringCache Ruby - Project Guide

## Purpose

This project builds and caches precompiled Ruby distributions using BoringCache, enabling near-instant Ruby installation for CI/CD pipelines and local development tools like [mise](https://mise.jdx.dev).

Instead of compiling Ruby from source on every CI run (which takes 5-15 minutes), users restore a prebuilt binary from BoringCache in seconds.

## How It Works

1. **Build**: We compile Ruby from source using the same process as [ruby-build](https://github.com/rbenv/ruby-build), with standard `./configure && make && make install` steps
2. **Cache**: Built binaries are uploaded to BoringCache with platform-specific tags
3. **Restore**: Users (or tools like mise) pull the cached binary and add it to PATH

Because we use the same configure options and directory structure as ruby-build, the resulting binaries are compatible with any Ruby version manager (rbenv, mise, asdf, chruby).

## Variants

Each Ruby version is built in 4 variants:

| Variant | Description | Use Case |
|---------|-------------|----------|
| `standard` | Base Ruby, no JIT, no jemalloc | Minimal footprint, maximum compatibility |
| `yjit` | YJIT JIT compiler enabled | Best runtime performance for most apps |
| `jemalloc` | jemalloc memory allocator | Reduced memory fragmentation for long-running processes |
| `jemalloc-yjit` | Both YJIT + jemalloc | Best performance + memory efficiency |

Windows only supports the `standard` variant due to MSYS2/MinGW limitations.

## Version Policy

- **Current major + 3 minor versions**, last 3 patch versions each
- Current: Ruby 4.0.x, 3.4.x, 3.3.x, 3.2.x
- Versions are dropped when they reach EOL (check https://endoflife.date/ruby)
- Latest patch gets `priority: high`, previous gets `medium`, oldest gets `low`

### versions.yml Structure

```yaml
versions:
  - version: "3.4.8"
    status: "stable"        # stable | preview
    priority: "high"        # high | medium | low (controls build order)
    maintenance: "normal"   # normal | security
    eol_date: "2028-03-31"
```

## Platform Support

Builds target all non-EOL platforms where GitHub Actions runners are available:

- **Ubuntu LTS** (22.04, 24.04) - native runners, amd64 + arm64
- **Ubuntu non-LTS** (25.04) - Docker builds
- **Debian** (Bookworm) - Docker builds, amd64 + arm64
- **Alpine Linux** - Docker builds, amd64 (musl libc)
- **Arch Linux** - Docker builds, amd64
- **macOS 15** - native runner, arm64
- **Windows** - native runner via MSYS2/MinGW, amd64 + arm64

## Cache Tag Format

The BoringCache CLI automatically appends the platform suffix:

```
ruby-{VERSION}[-{VARIANT}]-{PLATFORM}-{ARCH}
```

Examples:
- `ruby-3.4.8-ubuntu-22-04-amd64` (standard variant, no suffix)
- `ruby-3.4.8-yjit-macos-15-arm64`
- `ruby-3.4.8-jemalloc-yjit-debian-bookworm-arm64`

## Build System

- `Makefile` - Local development and CI entry points
- `scripts/build-ruby-variants.sh` - Main build script, handles parallel variant builds
- `scripts/configure-platform.sh` - Platform-specific configure flags
- `.github/workflows/build-ruby.yml` - CI workflow with dynamic matrix from versions.yml

### Key Make Targets

```bash
make build          # Build locally
make ci-build       # Build + upload (used by CI)
make dev-build-all  # Build all versions from versions.yml
make info           # Show current config
make versions       # Display version configuration
```

## Version Bump Automation

Version bumps are automated via `.github/workflows/check-ruby-versions.yml` which runs weekly, checks ruby-build for new patches, removes EOL versions, and opens a PR.

## Integration with mise

Users can configure mise to use BoringCache Ruby builds:

```toml
# .mise.toml
[tools]
ruby = "3.4.8"

[settings]
ruby_build_repo = "https://github.com/rbenv/ruby-build.git"
```

With a custom plugin or hook, mise can check BoringCache first before falling back to compiling from source.
