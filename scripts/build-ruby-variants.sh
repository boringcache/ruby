#!/bin/bash

set -euo pipefail

RUBY_VERSION="${1:-3.3.6}"
PLATFORM="${2:-linux}"
ARCH="${3:-amd64}"
VARIANTS="${4:-standard,yjit,jemalloc,jemalloc-yjit}"

BORINGCACHE_WORKSPACE="${BORINGCACHE_DEFAULT_WORKSPACE:-ruby/ruby}"
echo "Building Ruby $RUBY_VERSION for $PLATFORM-$ARCH with variants: $VARIANTS"

# Function to configure variant-specific options
configure_variant() {
    local variant="$1"

    case "$variant" in
        "standard")
            VARIANT_OPTS="--without-jemalloc --disable-yjit --with-gmp"
            ;;
        "yjit")
            VARIANT_OPTS="--without-jemalloc --enable-yjit --with-gmp"
            ;;
        "jemalloc")
            VARIANT_OPTS="--with-jemalloc --disable-yjit --with-gmp"
            ;;
        "jemalloc-yjit")
            VARIANT_OPTS="--with-jemalloc --enable-yjit --with-gmp"
            ;;
        *)
            echo "ERROR: Unknown variant: $variant"
            exit 1
            ;;
    esac
}

# Function to build a single variant
build_variant() {
    local variant="$1"
    echo "Building Ruby $RUBY_VERSION ($variant variant)"

    # Reset variant-specific variables
    local RUBY_BIN=""

    # Create variant-specific directories
    local RUBY_BASE_DIR="/tmp/ruby-${RUBY_VERSION}-${variant}-${ARCH}"
    local RUBY_PREFIX="$RUBY_BASE_DIR/ruby"
    local BUILD_DIR="/tmp/ruby-build-${RUBY_VERSION}-${variant}-${ARCH}"

    # Clean up any existing builds for this variant
    rm -rf "$RUBY_BASE_DIR" "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # Configure this variant
    configure_variant "$variant"

    # Set up Ruby configure options with variant-specific options
    RUBY_CONFIGURE_OPTS="--enable-shared --enable-load-relative --with-static-linked-ext --enable-frozen-string-literal --enable-pthread --enable-debug-env --enable-rubygems $VARIANT_OPTS"

    # Set platform-specific environment variables for macOS
    local BUILD_CPPFLAGS="${CPPFLAGS:-}"
    local BUILD_LDFLAGS="${LDFLAGS:-}"

    if [[ "$PLATFORM" == macos* ]] && command -v brew >/dev/null 2>&1; then
        HOMEBREW_PREFIX=$(brew --prefix)

        BUILD_CPPFLAGS="-I$HOMEBREW_PREFIX/include${BUILD_CPPFLAGS:+ $BUILD_CPPFLAGS}"
        BUILD_LDFLAGS="-L$HOMEBREW_PREFIX/lib${BUILD_LDFLAGS:+ $BUILD_LDFLAGS}"

        if [[ -d "$HOMEBREW_PREFIX/opt/openssl@3" ]]; then
            BUILD_CPPFLAGS="$BUILD_CPPFLAGS -I$HOMEBREW_PREFIX/opt/openssl@3/include"
            BUILD_LDFLAGS="$BUILD_LDFLAGS -L$HOMEBREW_PREFIX/opt/openssl@3/lib"
        fi

        if [[ -d "$HOMEBREW_PREFIX/opt/libyaml" ]]; then
            BUILD_CPPFLAGS="$BUILD_CPPFLAGS -I$HOMEBREW_PREFIX/opt/libyaml/include"
            BUILD_LDFLAGS="$BUILD_LDFLAGS -L$HOMEBREW_PREFIX/opt/libyaml/lib"
        fi

        # For jemalloc variants, add jemalloc paths
        if [[ "$variant" == "jemalloc" ]] || [[ "$variant" == "jemalloc-yjit" ]]; then
            JEMALLOC_PREFIX="$HOMEBREW_PREFIX/opt/jemalloc"
            if [[ -d "$JEMALLOC_PREFIX" ]]; then
                BUILD_CPPFLAGS="$BUILD_CPPFLAGS -I$JEMALLOC_PREFIX/include"
                BUILD_LDFLAGS="$BUILD_LDFLAGS -L$JEMALLOC_PREFIX/lib"
            else
                echo "⚠ jemalloc not found at $JEMALLOC_PREFIX - build may fail"
            fi
        fi
    fi

    # Export the build-specific flags
    export CPPFLAGS="$BUILD_CPPFLAGS"
    export LDFLAGS="$BUILD_LDFLAGS"

    # Get platform-specific configure options
    PLATFORM_OPTS=$(./scripts/configure-platform.sh "$PLATFORM" "$variant" "$ARCH")
    if [[ -n "$PLATFORM_OPTS" ]]; then
        RUBY_CONFIGURE_OPTS="$RUBY_CONFIGURE_OPTS $PLATFORM_OPTS"
    fi

    # Windows-specific option filtering
    if [[ "$PLATFORM" == "windows" ]]; then
        RUBY_CONFIGURE_OPTS=$(echo "$RUBY_CONFIGURE_OPTS" | sed 's/--with-static-linked-ext//g')
        RUBY_CONFIGURE_OPTS=$(echo "$RUBY_CONFIGURE_OPTS" | sed 's/--enable-yjit//g')
        RUBY_CONFIGURE_OPTS=$(echo "$RUBY_CONFIGURE_OPTS" | sed 's/--with-jemalloc//g')
    fi

    # Export configure options for ruby-build
    export RUBY_CONFIGURE_OPTS
    export RUBY_BUILD_VERBOSE=1

    # Build Ruby (only show verbose output on error)
    if ruby-build "$RUBY_VERSION" "$RUBY_PREFIX" 2>&1 | tee "/tmp/ruby-build-${variant}-output.log"; then
        echo "✓ Ruby build completed for variant: $variant"

        # Locate Ruby binary
        RUBY_BINARY=""
        if [[ "$PLATFORM" == "windows" ]]; then
            # On Windows/MSYS2, check multiple possible locations
            for alt_ruby in "$RUBY_PREFIX/bin/ruby.exe" "$RUBY_PREFIX/bin/ruby"; do
                if [[ -f "$alt_ruby" ]] && [[ -x "$alt_ruby" ]]; then
                    RUBY_BINARY="$alt_ruby"
                    break
                fi
            done
            # If not found, search in the base directory
            if [[ -z "$RUBY_BINARY" ]] && [[ -d "$RUBY_BASE_DIR" ]]; then
                RUBY_BINARY=$(find "$RUBY_BASE_DIR" -name "ruby.exe" -o -name "ruby" 2>/dev/null | head -1)
            fi
            # Last resort: parse the build log for actual install path
            if [[ -z "$RUBY_BINARY" ]]; then
                ACTUAL_PATH=$(grep "==> Installed ruby-$RUBY_VERSION to" "/tmp/ruby-build-${variant}-output.log" 2>/dev/null | sed 's/.*==> Installed ruby-[^ ]* to //')
                if [[ -n "$ACTUAL_PATH" ]]; then
                    for alt_ruby in "$ACTUAL_PATH/bin/ruby.exe" "$ACTUAL_PATH/bin/ruby"; do
                        if [[ -f "$alt_ruby" ]] && [[ -x "$alt_ruby" ]]; then
                            RUBY_BINARY="$alt_ruby"
                            RUBY_PREFIX="$ACTUAL_PATH"
                            break
                        fi
                    done
                fi
            fi
        else
            if [[ -f "$RUBY_PREFIX/bin/ruby" ]]; then
                RUBY_BINARY="$RUBY_PREFIX/bin/ruby"
            fi
        fi

        if [[ -n "$RUBY_BINARY" ]]; then
            # Test Ruby (set library path for shared builds)
            export LD_LIBRARY_PATH="$RUBY_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export DYLD_LIBRARY_PATH="$RUBY_PREFIX/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

            if "$RUBY_BINARY" --version; then
                echo "✓ Ruby is working for variant: $variant"
                return 0
            else
                # Create a wrapper script that sets the library path
                if [[ "$PLATFORM" != "windows" ]]; then
                    cat > "$RUBY_PREFIX/bin/ruby-wrapper" << EOF
#!/bin/bash
export LD_LIBRARY_PATH="$RUBY_PREFIX/lib:\${LD_LIBRARY_PATH}"
export DYLD_LIBRARY_PATH="$RUBY_PREFIX/lib:\${DYLD_LIBRARY_PATH}"
exec "$RUBY_BINARY" "\$@"
EOF
                    chmod +x "$RUBY_PREFIX/bin/ruby-wrapper"
                    if "$RUBY_PREFIX/bin/ruby-wrapper" --version; then
                        echo "✓ Ruby wrapper is working for variant: $variant"
                        return 0
                    fi
                fi
                echo "✗ Ruby execution failed for variant: $variant"
                return 1
            fi
        else
            echo "✗ Ruby binary not found for variant: $variant"
            return 1
        fi
    else
        echo "✗ Ruby build failed for variant: $variant"
        tail -50 "/tmp/ruby-build-${variant}-output.log" 2>/dev/null || true
        return 1
    fi
}

# Set architecture-specific variables
case "$ARCH" in
    "amd64"|"x86_64")
        ARCH_FLAG="x86_64"
        ;;
    "arm64"|"aarch64")
        ARCH_FLAG="aarch64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Install ruby-build if not available
if ! command -v ruby-build >/dev/null 2>&1; then
    echo "Installing ruby-build..."
    RUBY_BUILD_DIR="/tmp/ruby-build-$$"
    git clone --quiet https://github.com/rbenv/ruby-build.git "$RUBY_BUILD_DIR"
    export PATH="$RUBY_BUILD_DIR/bin:$PATH"
    echo "✓ ruby-build installed"
else
    echo "✓ ruby-build already available"
fi

# Determine which variants to build based on platform
determine_platform_variants() {
    case "$PLATFORM" in
        "windows")
            echo "standard"
            ;;
        *)
            echo "standard,yjit,jemalloc,jemalloc-yjit"
            ;;
    esac
}

# Override variants with platform-specific selection if not explicitly provided
if [[ "$VARIANTS" == "vanilla,yjit,jemalloc" ]] || [[ "$VARIANTS" == "standard,yjit,jemalloc" ]] || [[ "$VARIANTS" == "standard,yjit,jemalloc,jemalloc-yjit" ]]; then
    VARIANTS=$(determine_platform_variants)
fi

# Setup shared cache directory for ruby-build
SHARED_CACHE_DIR="/tmp/ruby-source-cache"
mkdir -p "$SHARED_CACHE_DIR"
export RUBY_BUILD_CACHE_PATH="$SHARED_CACHE_DIR"

# Pre-download Ruby source (tarball or git clone with locking)
RUBY_MAJOR=$(echo "$RUBY_VERSION" | cut -d. -f1-2)
RUBY_TARBALL="ruby-${RUBY_VERSION}.tar.gz"
CACHE_FILE="$SHARED_CACHE_DIR/$RUBY_TARBALL"

if [[ "$RUBY_VERSION" == *"-dev"* ]] || [[ "$RUBY_VERSION" == *"-preview"* ]] || [[ "$RUBY_VERSION" == *"-rc"* ]]; then
    GIT_CACHE_DIR="$SHARED_CACHE_DIR/https_github.com_ruby_ruby.git"
    LOCK_DIR="$SHARED_CACHE_DIR/.git-clone.lock"
    MAX_WAIT=300
    WAITED=0

    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        if [[ $WAITED -ge $MAX_WAIT ]]; then
            break
        fi
        sleep 5
        WAITED=$((WAITED + 5))
    done

    trap "rmdir '$LOCK_DIR' 2>/dev/null || true" EXIT

    if [[ ! -d "$GIT_CACHE_DIR" ]]; then
        echo "Cloning Ruby repository..."
        git clone --bare --quiet --branch master https://github.com/ruby/ruby.git "$GIT_CACHE_DIR"
    fi

    rmdir "$LOCK_DIR" 2>/dev/null || true
    trap - EXIT
else
    if [[ ! -f "$CACHE_FILE" ]]; then
        RUBY_URLS=(
            "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR}/ruby-${RUBY_VERSION}.tar.gz"
            "https://ftp.ruby-lang.org/pub/ruby/${RUBY_MAJOR}/ruby-${RUBY_VERSION}.tar.gz"
        )

        for url in "${RUBY_URLS[@]}"; do
            if curl -fsSL --connect-timeout 10 --max-time 300 -o "$CACHE_FILE" "$url" 2>/dev/null; then
                break
            fi
            rm -f "$CACHE_FILE"
        done
    fi
fi

# Build all variants in parallel
IFS=',' read -ra VARIANT_ARRAY <<< "$VARIANTS"
declare -a BUILT_VARIANTS=()
declare -a FAILED_VARIANTS=()

echo "Starting parallel builds for variants: ${VARIANT_ARRAY[*]}"

# Start all builds in background
BUILD_PIDS=()
VARIANT_PID_MAP=()

for CURRENT_VARIANT in "${VARIANT_ARRAY[@]}"; do
    CURRENT_VARIANT=$(echo "$CURRENT_VARIANT" | xargs)

    (
        export RUBY_BUILD_CACHE_PATH="$SHARED_CACHE_DIR"
        build_variant "$CURRENT_VARIANT" 2>&1 | tee "/tmp/build-${CURRENT_VARIANT}-full.log"
        exit ${PIPESTATUS[0]}
    ) &
    BUILD_PID=$!
    BUILD_PIDS+=($BUILD_PID)
    VARIANT_PID_MAP+=("$CURRENT_VARIANT:$BUILD_PID")
done

# Wait for all builds to complete and collect results
for pid_mapping in "${VARIANT_PID_MAP[@]}"; do
    variant="${pid_mapping%:*}"
    pid="${pid_mapping#*:}"

    if wait $pid; then
        echo "✓ Successfully built variant: $variant"
        BUILT_VARIANTS+=("$variant")
    else
        echo "✗ Failed to build variant: $variant"
        FAILED_VARIANTS+=("$variant")
        tail -30 "/tmp/build-${variant}-full.log" 2>/dev/null || true
    fi
done

echo ""
echo "Build results: ${#BUILT_VARIANTS[@]} succeeded, ${#FAILED_VARIANTS[@]} failed"

# Upload all successful builds
if (( ${#BUILT_VARIANTS[@]} )); then
  for variant in "${BUILT_VARIANTS[@]}"; do
    RUBY_BASE_DIR="/tmp/ruby-${RUBY_VERSION}-${variant}-${ARCH}"

    if command -v boringcache >/dev/null 2>&1; then
        if [[ "$variant" == "standard" ]]; then
            cache_tag="ruby-${RUBY_VERSION}"
        else
            cache_tag="ruby-${RUBY_VERSION}-${variant}"
        fi

        echo "Uploading $variant variant to BoringCache..."
        if boringcache save "$BORINGCACHE_WORKSPACE" "$cache_tag:$RUBY_BASE_DIR"; then
            echo "✓ Cached Ruby $RUBY_VERSION ($variant)"
        else
            echo "✗ Failed to cache Ruby $RUBY_VERSION ($variant)"
        fi
    fi
  done
fi

# Summary
echo ""
echo "Build Summary: Ruby $RUBY_VERSION for $PLATFORM-$ARCH"
if (( ${#BUILT_VARIANTS[@]} )); then
    echo "✓ Success: ${BUILT_VARIANTS[*]}"
fi
if (( ${#FAILED_VARIANTS[@]} )); then
    echo "✗ Failed: ${FAILED_VARIANTS[*]}"
    exit 1
fi
if (( ${#BUILT_VARIANTS[@]} == 0 )); then
    echo "✗ No variants were built successfully"
    exit 1
fi
echo "✓ All requested variants built successfully!"
