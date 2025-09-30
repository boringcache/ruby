#!/bin/bash

# Configure platform-specific build settings
# Usage: configure-platform.sh PLATFORM VARIANT ARCH

set -euo pipefail

PLATFORM="$1"
VARIANT="$2" 
ARCH="$3"

# Platform-specific configure options
case "$PLATFORM" in
    *ubuntu*|*debian*)
        echo "--with-coroutine=ucontext"
        ;;
    "alpine")
        # Alpine's musl libc doesn't support ucontext, use pthread instead
        echo "--with-coroutine=pthread"
        ;;
    "arch")
        EXTRA_OPTS="--with-coroutine=ucontext"
        # Ruby 3.1.x compatibility fixes for modern Arch Linux
        if [[ "${RUBY_VERSION:-}" =~ ^3\.1\. ]]; then
            echo "# Applying Ruby 3.1.x compatibility fixes for Arch Linux..." >&2
            export CFLAGS="-std=gnu99 -O2 -fno-strict-aliasing -Wno-error ${CFLAGS:-}"
            export CPPFLAGS="-DRUBY_EXPORT -DRUBY_UNTYPED_DATA_WARNING=0 ${CPPFLAGS:-}"
            EXTRA_OPTS="$EXTRA_OPTS --disable-shared"
        fi
        echo "$EXTRA_OPTS"
        ;;
    macos*)
        # Detect Homebrew and set paths
        if command -v brew >/dev/null 2>&1; then
            HOMEBREW_PREFIX=$(brew --prefix)
            export CPPFLAGS="${CPPFLAGS:-} -I$HOMEBREW_PREFIX/include"
            export LDFLAGS="${LDFLAGS:-} -L$HOMEBREW_PREFIX/lib"
            
            # Add specific library paths for common dependencies
            if [[ -d "$HOMEBREW_PREFIX/opt/libyaml" ]]; then
                export CPPFLAGS="$CPPFLAGS -I$HOMEBREW_PREFIX/opt/libyaml/include"
                export LDFLAGS="$LDFLAGS -L$HOMEBREW_PREFIX/opt/libyaml/lib"
                echo "# Added libyaml paths" >&2
            fi
            
            if [[ -d "$HOMEBREW_PREFIX/opt/openssl@3" ]]; then
                export CPPFLAGS="$CPPFLAGS -I$HOMEBREW_PREFIX/opt/openssl@3/include"
                export LDFLAGS="$LDFLAGS -L$HOMEBREW_PREFIX/opt/openssl@3/lib"
                echo "# Added OpenSSL paths" >&2
            fi
            
            echo "# Set macOS CPPFLAGS: $CPPFLAGS" >&2
            echo "# Set macOS LDFLAGS: $LDFLAGS" >&2
            
            # Set jemalloc prefix for all cases (used later for config options)
            JEMALLOC_PREFIX="$HOMEBREW_PREFIX/opt/jemalloc"
            
            # For jemalloc variant, add specific jemalloc paths
            if [[ "$VARIANT" == "jemalloc" ]]; then
                if [[ -d "$JEMALLOC_PREFIX" && -f "$JEMALLOC_PREFIX/include/jemalloc/jemalloc.h" && -f "$JEMALLOC_PREFIX/lib/libjemalloc.dylib" ]]; then
                    echo "# ✓ jemalloc found at $JEMALLOC_PREFIX" >&2
                    # Add jemalloc-specific paths to help configure find it
                    export CPPFLAGS="${CPPFLAGS} -I$JEMALLOC_PREFIX/include"
                    export LDFLAGS="${LDFLAGS} -L$JEMALLOC_PREFIX/lib"
                    echo "# Updated CPPFLAGS for jemalloc: $CPPFLAGS" >&2
                    echo "# Updated LDFLAGS for jemalloc: $LDFLAGS" >&2
                else
                    echo "# ✗ jemalloc not found at $JEMALLOC_PREFIX" >&2
                    echo "# Install with: brew install jemalloc" >&2
                    exit 1
                fi
            fi
        else
            echo "# ✗ Homebrew not found - required for macOS dependencies" >&2
            exit 1
        fi
        
        # macOS-specific configure options for better library detection
        # Note: jemalloc paths are handled via CPPFLAGS/LDFLAGS, not --with-jemalloc-dir
        MACOS_CONFIG_OPTS=("--with-libyaml-dir=$HOMEBREW_PREFIX/opt/libyaml" "--with-openssl-dir=$HOMEBREW_PREFIX/opt/openssl@3")
        
        echo "${MACOS_CONFIG_OPTS[*]}"
        ;;
    "windows")
        # Windows-specific configuration
        WINDOWS_OPTS="--with-out-ext=dbm,gdbm,readline"
        # Remove incompatible options and features for Windows
        echo "$WINDOWS_OPTS"
        ;;
    *)
        echo ""  # No extra options for unknown platforms
        ;;
esac