#!/bin/bash

set -euo pipefail

RUBY_VERSION="${1:-3.3.6}"
PLATFORM="${2:-linux}"
ARCH="${3:-amd64}"
VARIANTS="${4:-standard,yjit,jemalloc,jemalloc-yjit}"

# Resolve workspace preference: BORINGCACHE_DEFAULT_WORKSPACE > WORKSPACE >
# DEFAULT_BORINGCACHE_WORKSPACE env > built-in fallback
ENV_WORKSPACE="${WORKSPACE:-}"
ENV_DEFAULT_WORKSPACE="${DEFAULT_BORINGCACHE_WORKSPACE:-}"
DEFAULT_WORKSPACE_FALLBACK="${ENV_DEFAULT_WORKSPACE:-boringcache/ruby}"
BORINGCACHE_USE_CLI_DEFAULT=false

if [[ -n "${BORINGCACHE_DEFAULT_WORKSPACE:-}" ]]; then
    BORINGCACHE_WORKSPACE="$BORINGCACHE_DEFAULT_WORKSPACE"
    BORINGCACHE_USE_CLI_DEFAULT=true
    echo "Using BoringCache workspace from BORINGCACHE_DEFAULT_WORKSPACE: $BORINGCACHE_WORKSPACE"
elif [[ -n "$ENV_WORKSPACE" ]]; then
    BORINGCACHE_WORKSPACE="$ENV_WORKSPACE"
    echo "Using BoringCache workspace from WORKSPACE: $BORINGCACHE_WORKSPACE"
elif [[ -n "$ENV_DEFAULT_WORKSPACE" ]]; then
    BORINGCACHE_WORKSPACE="$ENV_DEFAULT_WORKSPACE"
    echo "Using BoringCache workspace from DEFAULT_BORINGCACHE_WORKSPACE: $BORINGCACHE_WORKSPACE"
else
    BORINGCACHE_WORKSPACE="$DEFAULT_WORKSPACE_FALLBACK"
    echo "Using default BoringCache workspace: $BORINGCACHE_WORKSPACE"
fi

echo "Building Ruby $RUBY_VERSION for $PLATFORM-$ARCH with variants: $VARIANTS"

# Function to configure variant-specific options
configure_variant() {
    local variant="$1"
    echo "Configuring variant: $variant"
    
    case "$variant" in
        "standard")
            VARIANT_OPTS="--without-jemalloc --disable-yjit --with-gmp"
            echo "✓ Configured variant: standard Ruby"
            ;;
        "yjit")
            VARIANT_OPTS="--without-jemalloc --enable-yjit --with-gmp"
            echo "✓ Configured variant: Ruby with YJIT JIT compiler"
            ;;
        "jemalloc")
            # Don't use --with-jemalloc-dir on macOS, it doesn't work properly
            # Instead rely on CPPFLAGS and LDFLAGS being set correctly
            VARIANT_OPTS="--with-jemalloc --disable-yjit --with-gmp"
            echo "✓ Configured variant: Ruby with jemalloc memory allocator"
            ;;
        "jemalloc-yjit")
            # Combined variant with both jemalloc and YJIT enabled
            VARIANT_OPTS="--with-jemalloc --enable-yjit --with-gmp"
            echo "✓ Configured variant: Ruby with jemalloc memory allocator and YJIT JIT compiler"
            ;;
        *)
            echo "ERROR: Unknown variant: $variant"
            echo "Available variants: standard, yjit, jemalloc, jemalloc-yjit"
            exit 1
            ;;
    esac
}

# Function to build a single variant
build_variant() {
    local variant="$1"
    echo ""
    echo "========================================"
    echo "Building Ruby $RUBY_VERSION ($variant variant)"
    echo "========================================"
    
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
    # Note: --enable-load-relative helps with portability for shared builds
    RUBY_CONFIGURE_OPTS="--enable-shared --enable-load-relative --with-static-linked-ext --enable-frozen-string-literal --enable-pthread --enable-debug-env --enable-rubygems $VARIANT_OPTS"
    
    # Set platform-specific environment variables for macOS
    # Use local variables to avoid polluting environment for parallel builds
    local BUILD_CPPFLAGS="${CPPFLAGS:-}"
    local BUILD_LDFLAGS="${LDFLAGS:-}"
    
    if [[ "$PLATFORM" == macos* ]] && command -v brew >/dev/null 2>&1; then
        HOMEBREW_PREFIX=$(brew --prefix)
        
        # IMPORTANT: Set the general Homebrew paths FIRST
        # This is critical for configure to find libraries
        BUILD_CPPFLAGS="-I$HOMEBREW_PREFIX/include${BUILD_CPPFLAGS:+ $BUILD_CPPFLAGS}"
        BUILD_LDFLAGS="-L$HOMEBREW_PREFIX/lib${BUILD_LDFLAGS:+ $BUILD_LDFLAGS}"
        
        # Add specific paths for dependencies (these go AFTER the general paths)
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
                echo "✓ Added jemalloc paths: $JEMALLOC_PREFIX"
                
                # Check if jemalloc headers actually exist
                if [[ -f "$JEMALLOC_PREFIX/include/jemalloc/jemalloc.h" ]]; then
                    echo "  ✓ Found jemalloc.h at expected location"
                else
                    echo "  ✗ jemalloc.h not found at $JEMALLOC_PREFIX/include/jemalloc/jemalloc.h"
                    echo "  Directory contents:"
                    ls -la "$JEMALLOC_PREFIX/include/" 2>/dev/null || echo "    Include directory not found"
                fi
            else
                echo "⚠ jemalloc not found at $JEMALLOC_PREFIX - build may fail"
                echo "  Install with: brew install jemalloc"
            fi
        fi
        
        echo "macOS build environment for $variant:"
        echo "  CPPFLAGS: $BUILD_CPPFLAGS"
        echo "  LDFLAGS: $BUILD_LDFLAGS"
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
        # Remove incompatible options for Windows
        RUBY_CONFIGURE_OPTS=$(echo "$RUBY_CONFIGURE_OPTS" | sed 's/--with-static-linked-ext//g')
        # Disable features not supported on Windows
        RUBY_CONFIGURE_OPTS=$(echo "$RUBY_CONFIGURE_OPTS" | sed 's/--enable-yjit//g')
        RUBY_CONFIGURE_OPTS=$(echo "$RUBY_CONFIGURE_OPTS" | sed 's/--with-jemalloc//g')
    fi
    
    echo "Building Ruby $RUBY_VERSION ($variant variant) for $PLATFORM-$ARCH"
    echo "Configure options: $RUBY_CONFIGURE_OPTS"
    
    # Debug: Show all environment variables that affect the build
    echo "Build environment variables:"
    echo "  CPPFLAGS: $CPPFLAGS"
    echo "  LDFLAGS: $LDFLAGS"
    echo "  RUBY_CFLAGS: ${RUBY_CFLAGS:-not set}"
    echo "  RUBY_LDFLAGS: ${RUBY_LDFLAGS:-not set}"
    echo "  RUBY_CONFIGURE_OPTS: $RUBY_CONFIGURE_OPTS"
    
    # Export configure options for ruby-build
    export RUBY_CONFIGURE_OPTS
    export RUBY_BUILD_VERBOSE=1
    
    # For debugging jemalloc issues on macOS
    if ([[ "$variant" == "jemalloc" ]] || [[ "$variant" == "jemalloc-yjit" ]]) && [[ "$PLATFORM" == macos* ]]; then
        echo "Debugging jemalloc detection:"
        # Check if we can compile a simple jemalloc test
        if command -v brew >/dev/null 2>&1; then
            HOMEBREW_PREFIX=$(brew --prefix)
            echo "  Homebrew prefix: $HOMEBREW_PREFIX"
            echo "  Checking for jemalloc files:"
            ls -la "$HOMEBREW_PREFIX/opt/jemalloc/include/jemalloc/" 2>/dev/null | head -5 || echo "    jemalloc include dir not found"
            ls -la "$HOMEBREW_PREFIX/opt/jemalloc/lib/" 2>/dev/null | grep jemalloc || echo "    jemalloc lib not found"
            
            # Test if compiler can find jemalloc with our flags
            echo "  Testing compiler with CPPFLAGS and LDFLAGS:"
            echo '#include <jemalloc/jemalloc.h>' > /tmp/test_jemalloc.c
            echo 'int main() { return 0; }' >> /tmp/test_jemalloc.c
            if cc $CPPFLAGS $LDFLAGS /tmp/test_jemalloc.c -o /tmp/test_jemalloc 2>/dev/null; then
                echo "    ✓ Compiler can find jemalloc with current flags"
            else
                echo "    ✗ Compiler cannot find jemalloc with current flags"
                echo "    Trying with explicit paths:"
                if cc -I"$HOMEBREW_PREFIX/opt/jemalloc/include" -L"$HOMEBREW_PREFIX/opt/jemalloc/lib" /tmp/test_jemalloc.c -o /tmp/test_jemalloc 2>/dev/null; then
                    echo "    ✓ Compiler finds jemalloc with explicit paths"
                else
                    echo "    ✗ Compiler still cannot find jemalloc"
                fi
            fi
            rm -f /tmp/test_jemalloc.c /tmp/test_jemalloc
        fi
    fi
    
    # Build Ruby using ruby-build (source already pre-downloaded to shared cache)
    echo "Starting ruby-build for $RUBY_VERSION to $RUBY_PREFIX"
    
    if [[ "$PLATFORM" == "windows" ]]; then
        echo "Windows: ruby-build will install to: $RUBY_PREFIX"
        echo "Windows: Current PWD: $(pwd)"
        echo "Windows: TMP/TEMP directories:"
        echo "  TEMP: ${TEMP:-not set}"
        echo "  TMP: ${TMP:-not set}"
        echo "  TMPDIR: ${TMPDIR:-not set}"
    fi
    
    echo "Building with shared source cache: $RUBY_BUILD_CACHE_PATH"
    echo "Checking cache directory contents:"
    if [[ -d "$RUBY_BUILD_CACHE_PATH" ]]; then
        ls -la "$RUBY_BUILD_CACHE_PATH/" | head -5
    else
        echo "Cache directory doesn't exist!"
    fi
    
    # Build Ruby (only show verbose output on error)
    if ruby-build "$RUBY_VERSION" "$RUBY_PREFIX" 2>&1 | tee "/tmp/ruby-build-${variant}-output.log"; then
        echo "✓ Ruby build completed successfully for variant: $variant"
        
        # Verify the build (check for platform-specific binary names)
        echo "Looking for Ruby binary in: $RUBY_PREFIX/bin/"
        
        # First check what was actually installed
        echo "Checking installation directory structure:"
        
        # On Windows/MSYS2, try simpler approach using which/where commands
        if [[ "$PLATFORM" == "windows" ]]; then
            echo "Windows: ruby-build reported installation to: $RUBY_PREFIX"
            echo "Windows: Checking if directory exists as reported..."
            
            # Try the reported path first
            if [[ ! -d "$RUBY_PREFIX" ]]; then
                echo "✗ Reported path doesn't exist, trying to locate Ruby binary..."
                
                # Method 1: Try to find ruby binary by adding expected path to PATH and using which
                echo "Method 1: Adding expected bin path to PATH and using 'which ruby'..."
                # Temporarily add the expected bin directory to PATH
                EXPECTED_BIN_DIRS=("$RUBY_PREFIX/bin")
                
                # Also try Windows path variations
                for drive in "C" "D" "E"; do
                    WIN_PREFIX=$(echo "$RUBY_PREFIX" | sed "s|^/tmp|${drive}:/a/_temp/msys64/tmp|")
                    EXPECTED_BIN_DIRS+=("$WIN_PREFIX/bin")
                done
                
                for bin_dir in "${EXPECTED_BIN_DIRS[@]}"; do
                    if [[ -d "$bin_dir" ]]; then
                        echo "Found bin directory: $bin_dir"
                        # Temporarily add to PATH
                        export PATH="$bin_dir:$PATH"
                        
                        # Try to find ruby
                        RUBY_BINARY_PATH=$(which ruby 2>/dev/null || where ruby.exe 2>/dev/null || echo "")
                        if [[ -n "$RUBY_BINARY_PATH" ]]; then
                            # Extract installation directory
                            RUBY_PREFIX_FROM_BINARY=$(dirname "$(dirname "$RUBY_BINARY_PATH")" 2>/dev/null)
                            if [[ -d "$RUBY_PREFIX_FROM_BINARY" ]]; then
                                echo "✓ Found Ruby installation via 'which': $RUBY_PREFIX_FROM_BINARY"
                                RUBY_PREFIX="$RUBY_PREFIX_FROM_BINARY"
                                break
                            fi
                        fi
                    fi
                done
                
                # Method 2: Parse build log if Method 1 failed
                if [[ ! -d "$RUBY_PREFIX" ]]; then
                    echo "Method 2: Parsing ruby-build output log..."
                    BUILD_LOG="/tmp/ruby-build-${variant}-output.log"
                    if [[ -f "$BUILD_LOG" ]]; then
                        ACTUAL_INSTALL_PATH=$(grep "==> Installed ruby-$RUBY_VERSION to" "$BUILD_LOG" | tail -1 | sed 's/.*==> Installed ruby-[^ ]* to //')
                        if [[ -n "$ACTUAL_INSTALL_PATH" ]] && [[ -d "$ACTUAL_INSTALL_PATH" ]]; then
                            echo "✓ Found Ruby installation from log: $ACTUAL_INSTALL_PATH"
                            RUBY_PREFIX="$ACTUAL_INSTALL_PATH"
                        elif [[ -n "$ACTUAL_INSTALL_PATH" ]]; then
                            echo "Log shows path: $ACTUAL_INSTALL_PATH, but directory doesn't exist"
                            
                            # Try Windows drive mapping
                            for drive in "C" "D" "E"; do
                                WIN_PATH=$(echo "$ACTUAL_INSTALL_PATH" | sed "s|^/tmp|${drive}:/a/_temp/msys64/tmp|")
                                if [[ -d "$WIN_PATH" ]]; then
                                    # Convert back to UNIX path if possible
                                    if command -v cygpath >/dev/null 2>&1; then
                                        RUBY_PREFIX=$(cygpath -u "$WIN_PATH" 2>/dev/null || echo "$WIN_PATH")
                                    else
                                        RUBY_PREFIX="$WIN_PATH"
                                    fi
                                    echo "✓ Found Ruby at Windows path: $WIN_PATH -> $RUBY_PREFIX"
                                    break
                                fi
                            done
                        fi
                    fi
                fi
                
                # Method 3: Search filesystem as last resort
                if [[ ! -d "$RUBY_PREFIX" ]]; then
                    echo "Method 3: Searching filesystem for Ruby installation..."
                    SEARCH_PATTERN="ruby-$RUBY_VERSION-$variant-$ARCH"
                    for search_base in "/c" "/d" "/e" "/tmp"; do
                        if [[ -d "$search_base" ]]; then
                            FOUND_RUBY=$(find "$search_base" -name "$SEARCH_PATTERN" -type d 2>/dev/null | head -1)
                            if [[ -n "$FOUND_RUBY" ]]; then
                                if [[ -d "$FOUND_RUBY/ruby/bin" ]]; then
                                    RUBY_PREFIX="$FOUND_RUBY/ruby"
                                    echo "✓ Found Ruby via search: $RUBY_PREFIX"
                                    break
                                elif [[ -d "$FOUND_RUBY/bin" ]]; then
                                    RUBY_PREFIX="$FOUND_RUBY"
                                    echo "✓ Found Ruby (direct) via search: $RUBY_PREFIX"
                                    break
                                fi
                            fi
                        fi
                    done
                fi
            else
                echo "✓ Ruby installation found at reported path: $RUBY_PREFIX"
            fi
        fi
        
        if [[ -d "$RUBY_PREFIX" ]]; then
            echo "Contents of $RUBY_PREFIX:"
            ls -la "$RUBY_PREFIX/" 2>/dev/null | head -10
            
            # Check common subdirectories
            for subdir in bin lib share include; do
                if [[ -d "$RUBY_PREFIX/$subdir" ]]; then
                    echo "Found $subdir directory"
                fi
            done
        else
            echo "ERROR: Installation directory does not exist at $RUBY_PREFIX"
            echo "Checking parent directory $RUBY_BASE_DIR:"
            ls -la "$RUBY_BASE_DIR/" 2>/dev/null | head -10
            
            # Windows-specific debugging - check for different path formats
            if [[ "$PLATFORM" == "windows" ]]; then
                echo "Windows/MSYS2 debugging - checking path resolution:"
                echo "Current working directory: $(pwd)"
                echo "Original RUBY_PREFIX: $RUBY_PREFIX"
                echo "Environment variables:"
                echo "  TEMP: ${TEMP:-not set}"
                echo "  TMP: ${TMP:-not set}"
                echo "  TMPDIR: ${TMPDIR:-not set}"
                
                # In MSYS2, /tmp is typically mapped to a Windows path
                # Let's find where ruby-build actually installed Ruby
                echo "Searching for Ruby installation in all possible locations..."
                
                # Try to find the installation using various search strategies
                FOUND_RUBY_DIR=""
                
                # Strategy 1: Check actual filesystem for ruby-build output pattern
                echo "Strategy 1: Searching filesystem for ruby-$RUBY_VERSION-$variant-$ARCH"
                for search_root in "/tmp" "/var/tmp" "/c/tmp" "/c/temp" "$HOME/tmp" "/usr/tmp"; do
                    if [[ -d "$search_root" ]]; then
                        echo "  Searching in: $search_root"
                        FOUND_DIRS=$(find "$search_root" -maxdepth 3 -name "*ruby-$RUBY_VERSION*" -type d 2>/dev/null || true)
                        if [[ -n "$FOUND_DIRS" ]]; then
                            echo "  Found ruby directories:"
                            echo "$FOUND_DIRS" | while read dir; do echo "    $dir"; done
                            
                            # Look for our specific pattern
                            SPECIFIC_DIR=$(echo "$FOUND_DIRS" | grep "ruby-$RUBY_VERSION-$variant-$ARCH" | head -1)
                            if [[ -n "$SPECIFIC_DIR" ]]; then
                                if [[ -d "$SPECIFIC_DIR/ruby" ]]; then
                                    FOUND_RUBY_DIR="$SPECIFIC_DIR/ruby"
                                    echo "  ✓ Found matching installation: $FOUND_RUBY_DIR"
                                    break
                                elif [[ -d "$SPECIFIC_DIR/bin" ]]; then
                                    FOUND_RUBY_DIR="$SPECIFIC_DIR"
                                    echo "  ✓ Found matching installation (direct): $FOUND_RUBY_DIR"
                                    break
                                fi
                            fi
                        fi
                    fi
                done
                
                # Strategy 2: Check Windows-specific MSYS2 temp mappings
                if [[ -z "$FOUND_RUBY_DIR" ]]; then
                    echo "Strategy 2: Checking MSYS2 Windows temp mappings"
                    # Get the actual Windows temp directory that MSYS2 might be using
                    if command -v cygpath >/dev/null 2>&1; then
                        WIN_TEMP=$(cygpath -u "$TEMP" 2>/dev/null || echo "")
                        if [[ -n "$WIN_TEMP" ]] && [[ -d "$WIN_TEMP" ]]; then
                            echo "  Windows TEMP mapped to: $WIN_TEMP"
                            TEMP_RUBY_DIR=$(find "$WIN_TEMP" -name "*ruby-$RUBY_VERSION-$variant-$ARCH*" -type d 2>/dev/null | head -1)
                            if [[ -n "$TEMP_RUBY_DIR" ]]; then
                                if [[ -d "$TEMP_RUBY_DIR/ruby" ]]; then
                                    FOUND_RUBY_DIR="$TEMP_RUBY_DIR/ruby"
                                elif [[ -d "$TEMP_RUBY_DIR/bin" ]]; then
                                    FOUND_RUBY_DIR="$TEMP_RUBY_DIR"
                                fi
                                echo "  ✓ Found in Windows temp: $FOUND_RUBY_DIR"
                            fi
                        fi
                    fi
                fi
                
                # Strategy 3: Use find with broader search pattern
                if [[ -z "$FOUND_RUBY_DIR" ]]; then
                    echo "Strategy 3: Broad filesystem search"
                    echo "  Searching entire filesystem for ruby-$RUBY_VERSION installations..."
                    # Search from root, but limit depth and exclude problematic directories
                    BROAD_SEARCH=$(find / -maxdepth 4 -name "*ruby-$RUBY_VERSION*" -type d \
                        -not -path "/proc/*" -not -path "/sys/*" -not -path "/dev/*" \
                        2>/dev/null | head -10)
                    if [[ -n "$BROAD_SEARCH" ]]; then
                        echo "  Found ruby installations:"
                        echo "$BROAD_SEARCH" | while read dir; do echo "    $dir"; done
                        
                        # Look for our variant
                        VARIANT_DIR=$(echo "$BROAD_SEARCH" | grep "$variant" | head -1)
                        if [[ -n "$VARIANT_DIR" ]]; then
                            if [[ -d "$VARIANT_DIR/ruby/bin" ]]; then
                                FOUND_RUBY_DIR="$VARIANT_DIR/ruby"
                            elif [[ -d "$VARIANT_DIR/bin" ]]; then
                                FOUND_RUBY_DIR="$VARIANT_DIR"
                            fi
                            echo "  ✓ Found variant installation: $FOUND_RUBY_DIR"
                        fi
                    fi
                fi
                
                # Update RUBY_PREFIX if we found the installation
                if [[ -n "$FOUND_RUBY_DIR" ]]; then
                    echo "SUCCESS: Found Ruby installation at: $FOUND_RUBY_DIR"
                    RUBY_PREFIX="$FOUND_RUBY_DIR"
                    echo "Updated RUBY_PREFIX to: $RUBY_PREFIX"
                else
                    echo "ERROR: Could not locate Ruby installation anywhere on filesystem"
                    echo "This suggests ruby-build failed silently or installed to an unexpected location"
                    
                    # Last resort: check what ruby-build actually output
                    echo "Checking ruby-build output log for clues:"
                    if [[ -f "/tmp/ruby-build-${variant}-output.log" ]]; then
                        echo "Last 20 lines of ruby-build output:"
                        tail -20 "/tmp/ruby-build-${variant}-output.log"
                        
                        # Look for installation path in the log
                        INSTALL_HINT=$(grep -i "installed\|prefix\|destination" "/tmp/ruby-build-${variant}-output.log" | tail -5)
                        if [[ -n "$INSTALL_HINT" ]]; then
                            echo "Installation hints from log:"
                            echo "$INSTALL_HINT"
                        fi
                    fi
                fi
            fi
        fi
        
        # List what's actually in the bin directory
        if [[ -d "$RUBY_PREFIX/bin" ]]; then
            echo "Contents of $RUBY_PREFIX/bin:"
            ls -la "$RUBY_PREFIX/bin/" | head -20
        else
            echo "ERROR: bin directory does not exist at $RUBY_PREFIX/bin"
        fi
        
        RUBY_BINARY=""
        if [[ "$PLATFORM" == "windows" ]]; then
            # Windows uses .exe extension
            echo "Checking for Windows binary: $RUBY_PREFIX/bin/ruby.exe"
            
            # Try multiple possible locations where ruby-build might install on Windows
            POSSIBLE_LOCATIONS=(
                "$RUBY_PREFIX/bin/ruby.exe"
                "$RUBY_PREFIX/bin/ruby"
                "$RUBY_BASE_DIR/bin/ruby.exe"
                "$RUBY_BASE_DIR/bin/ruby"
                "$RUBY_BASE_DIR/ruby.exe"
                "$RUBY_BASE_DIR/ruby"
            )
            
            # Also check if ruby-build created the binary with a different naming pattern
            if [[ -d "$RUBY_PREFIX/bin" ]]; then
                # Find any executable that starts with 'ruby'
                for exe in "$RUBY_PREFIX/bin"/ruby*; do
                    if [[ -x "$exe" ]]; then
                        POSSIBLE_LOCATIONS+=("$exe")
                    fi
                done
            fi
            
            for alt_ruby in "${POSSIBLE_LOCATIONS[@]}"; do
                echo "Checking location: $alt_ruby"
                if [[ -f "$alt_ruby" ]] && [[ -x "$alt_ruby" ]]; then
                    RUBY_BINARY="$alt_ruby"
                    echo "Found Ruby at: $alt_ruby"
                    break
                fi
            done
            
            # If still not found, try using find command in the base directory
            if [[ -z "$RUBY_BINARY" ]] && [[ -d "$RUBY_BASE_DIR" ]]; then
                echo "Searching for ruby executable in $RUBY_BASE_DIR..."
                FOUND_RUBY=$(find "$RUBY_BASE_DIR" -name "ruby.exe" -o -name "ruby" 2>/dev/null | head -1)
                if [[ -n "$FOUND_RUBY" ]] && [[ -f "$FOUND_RUBY" ]]; then
                    RUBY_BINARY="$FOUND_RUBY"
                    echo "Found Ruby via search: $FOUND_RUBY"
                fi
            fi
        else
            # Unix-like systems
            echo "Checking for Unix binary: $RUBY_PREFIX/bin/ruby"
            if [[ -f "$RUBY_PREFIX/bin/ruby" ]]; then
                RUBY_BINARY="$RUBY_PREFIX/bin/ruby"
                echo "Found Unix Ruby binary"
            fi
        fi
        
        if [[ -n "$RUBY_BINARY" ]]; then
            echo "✓ Ruby binary found for variant: $variant at $RUBY_BINARY"
            
            # Debug: Check installed files
            echo "Debug: Checking Ruby installation structure..."
            echo "Contents of $RUBY_PREFIX/bin/:"
            ls -la "$RUBY_PREFIX/bin/" 2>/dev/null || echo "bin directory not accessible"
            
            if [[ "$PLATFORM" != "windows" ]]; then
                echo "Checking for shared libraries..."
                ls -la "$RUBY_PREFIX/lib/"libru* 2>/dev/null || echo "No libru* files found"
            fi
            
            # Test Ruby (set library path for shared builds)
            export LD_LIBRARY_PATH="$RUBY_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export DYLD_LIBRARY_PATH="$RUBY_PREFIX/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
            
            echo "Testing Ruby with LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
            if "$RUBY_BINARY" --version; then
                echo "✓ Ruby is working for variant: $variant"
                RUBY_BIN="$RUBY_BINARY"
            else
                echo "⚠ Direct Ruby execution failed, creating wrapper script..."
                
                # Create a wrapper script that sets the library path
                if [[ "$PLATFORM" == "windows" ]]; then
                    # Windows wrapper (batch file)
                    cat > "$RUBY_PREFIX/bin/ruby-wrapper.bat" << EOF
@echo off
set PATH=$RUBY_PREFIX\\bin;%PATH%
"$RUBY_BINARY" %*
EOF
                    WRAPPER_SCRIPT="$RUBY_PREFIX/bin/ruby-wrapper.bat"
                else
                    # Unix wrapper (shell script)
                    cat > "$RUBY_PREFIX/bin/ruby-wrapper" << EOF
#!/bin/bash
export LD_LIBRARY_PATH="$RUBY_PREFIX/lib:\${LD_LIBRARY_PATH}"
export DYLD_LIBRARY_PATH="$RUBY_PREFIX/lib:\${DYLD_LIBRARY_PATH}"
exec "$RUBY_BINARY" "\$@"
EOF
                    chmod +x "$RUBY_PREFIX/bin/ruby-wrapper"
                    WRAPPER_SCRIPT="$RUBY_PREFIX/bin/ruby-wrapper"
                fi
                
                # Test with wrapper
                if "$WRAPPER_SCRIPT" --version; then
                    echo "✓ Ruby wrapper is working for variant: $variant"
                    # Use wrapper for SBOM generation
                    RUBY_BIN="$WRAPPER_SCRIPT"
                else
                    echo "✗ Ruby wrapper also failed for variant: $variant"
                    FAILED_VARIANTS+=("$variant")
                    return 1
                fi
            fi
            
            # Generate SBOM
            echo "Generating SBOM for Ruby $RUBY_VERSION ($variant variant)..."
            if ./scripts/generate-sbom.sh "$variant" "$RUBY_PREFIX" "$RUBY_BIN" "$RUBY_VERSION" "$PLATFORM" "$ARCH"; then
                echo "✓ SBOM generated successfully"
            else
                echo "✗ SBOM generation failed"
            fi
            
            # Mark build as successful (upload will happen later)
            echo "✓ Build completed for variant: $variant"
            echo "Build directory: $RUBY_BASE_DIR"
            return 0
        else
            echo "✗ Ruby binary not found for variant: $variant"
            return 1
        fi
    else
        echo "✗ Ruby build failed for variant: $variant"
        echo "Last 50 lines of build log:"
        echo "----------------------------------------"
        tail -50 "/tmp/ruby-build-${variant}-output.log" 2>/dev/null || echo "No build log found"
        echo "----------------------------------------"
        return 1
    fi
}

# Function to generate SBOM for Ruby installation
generate_sbom() {
    local variant="$1"
    local ruby_prefix="$2"
    local ruby_bin="${3:-$ruby_prefix/bin/ruby}"
    
    # Use external SBOM generation script
    ./scripts/generate-sbom.sh "$variant" "$ruby_prefix" "$ruby_bin" "$RUBY_VERSION" "$PLATFORM" "$ARCH"
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
    
    # Clone ruby-build to a temporary directory
    RUBY_BUILD_DIR="/tmp/ruby-build-$$"
    git clone https://github.com/rbenv/ruby-build.git "$RUBY_BUILD_DIR"
    
    # Make ruby-build available for this session
    export PATH="$RUBY_BUILD_DIR/bin:$PATH"
    
    echo "✓ ruby-build installed to $RUBY_BUILD_DIR"
else
    echo "✓ ruby-build already available"
fi

# Determine which variants to build based on platform
determine_platform_variants() {
    case "$PLATFORM" in
        "windows")
            # Windows only supports standard Ruby
            echo "standard"
            ;;
        "alpine")
            # Alpine supports all variants (with pthread coroutines)
            echo "standard,yjit,jemalloc,jemalloc-yjit"
            ;;
        *)
            # Most platforms support all variants
            echo "standard,yjit,jemalloc,jemalloc-yjit"
            ;;
    esac
}

# Override variants with platform-specific selection if not explicitly provided
if [[ "$VARIANTS" == "vanilla,yjit,jemalloc" ]] || [[ "$VARIANTS" == "standard,yjit,jemalloc" ]] || [[ "$VARIANTS" == "standard,yjit,jemalloc,jemalloc-yjit" ]]; then
    # Default variants provided, adjust for platform
    VARIANTS=$(determine_platform_variants)
    echo "Platform $PLATFORM supports variants: $VARIANTS"
fi

# Setup shared cache directory for ruby-build
echo "========================================"
echo "Setting up shared cache for Ruby builds"
echo "========================================"

SHARED_CACHE_DIR="/tmp/ruby-source-cache"
mkdir -p "$SHARED_CACHE_DIR"
export RUBY_BUILD_CACHE_PATH="$SHARED_CACHE_DIR"

echo "✓ Shared cache directory created at: $SHARED_CACHE_DIR"

# Pre-download Ruby source tarball (without building)
echo "Pre-downloading Ruby $RUBY_VERSION source tarball..."
RUBY_MAJOR=$(echo "$RUBY_VERSION" | cut -d. -f1-2)
RUBY_TARBALL="ruby-${RUBY_VERSION}.tar.gz"
CACHE_FILE="$SHARED_CACHE_DIR/$RUBY_TARBALL"

if [[ ! -f "$CACHE_FILE" ]]; then
    # Try to download from official Ruby sources
    RUBY_URLS=(
        "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR}/ruby-${RUBY_VERSION}.tar.gz"
        "https://ftp.ruby-lang.org/pub/ruby/${RUBY_MAJOR}/ruby-${RUBY_VERSION}.tar.gz"
        "https://www.ruby-lang.org/pub/ruby/${RUBY_MAJOR}/ruby-${RUBY_VERSION}.tar.gz"
    )
    
    DOWNLOAD_SUCCESS=false
    for url in "${RUBY_URLS[@]}"; do
        echo "Attempting download from: $url"
        if curl -fsSL --connect-timeout 10 --max-time 300 -o "$CACHE_FILE" "$url"; then
            echo "✓ Successfully downloaded Ruby source to cache"
            DOWNLOAD_SUCCESS=true
            break
        else
            echo "Failed to download from $url, trying next mirror..."
            rm -f "$CACHE_FILE"
        fi
    done
    
    if [[ "$DOWNLOAD_SUCCESS" = false ]]; then
        echo "⚠ Could not pre-download Ruby source, ruby-build will handle downloads"
        # Don't fail - let ruby-build handle it
    fi
else
    echo "✓ Ruby source already cached at: $CACHE_FILE"
fi

# Build all variants in parallel
IFS=',' read -ra VARIANT_ARRAY <<< "$VARIANTS"
declare -a BUILT_VARIANTS=()
declare -a FAILED_VARIANTS=()

echo "========================================"
echo "Starting parallel builds for variants: ${VARIANT_ARRAY[*]}"
echo "System resources:"
echo "  CPU cores: $(nproc 2>/dev/null || echo 'unknown')"
echo "  Memory: $(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo 'unknown')"
echo "  Disk space: $(df -h /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo 'unknown')"
echo "========================================"

# Start all builds in background
BUILD_PIDS=()
VARIANT_PID_MAP=()

for CURRENT_VARIANT in "${VARIANT_ARRAY[@]}"; do
    CURRENT_VARIANT=$(echo "$CURRENT_VARIANT" | xargs)  # trim whitespace
    
    echo "Starting build for variant: $CURRENT_VARIANT"
    
    # Build in a subshell to isolate environment variables between parallel builds
    (
        # Ensure cache path is available in subshell
        export RUBY_BUILD_CACHE_PATH="$SHARED_CACHE_DIR"
        build_variant "$CURRENT_VARIANT" 2>&1 | tee "/tmp/build-${CURRENT_VARIANT}-full.log"
        exit ${PIPESTATUS[0]}  # Preserve exit code of build_variant
    ) &
    BUILD_PID=$!
    BUILD_PIDS+=($BUILD_PID)
    VARIANT_PID_MAP+=("$CURRENT_VARIANT:$BUILD_PID")
    
    echo "Started variant $CURRENT_VARIANT with PID $BUILD_PID"
done

echo ""
echo "All variants started in parallel. Waiting for completion..."
echo "Build PIDs: ${BUILD_PIDS[*]}"
echo ""

# Wait for all builds to complete and collect results
for pid_mapping in "${VARIANT_PID_MAP[@]}"; do
    variant="${pid_mapping%:*}"
    pid="${pid_mapping#*:}"
    
    echo "Waiting for variant $variant (PID: $pid)..."
    
    # Wait for build with timeout monitoring
    if wait $pid; then
        echo "✓ Successfully built variant: $variant"
        BUILT_VARIANTS+=("$variant")
    else
        echo "✗ Failed to build variant: $variant"
        FAILED_VARIANTS+=("$variant")
        
        # Show error details from the full log
        if [[ -f "/tmp/build-${variant}-full.log" ]]; then
            echo "Last 30 lines of $variant build output:"
            echo "----------------------------------------"
            tail -30 "/tmp/build-${variant}-full.log"
            echo "----------------------------------------"
        fi
    fi
done

# Show progress summary
echo ""
echo "Parallel build results:"
echo "  Built variants: ${#BUILT_VARIANTS[@]}"
echo "  Failed variants: ${#FAILED_VARIANTS[@]}"
if (( ${#BUILT_VARIANTS[@]} )); then
    echo "  Success: ${BUILT_VARIANTS[*]}"
fi
if (( ${#FAILED_VARIANTS[@]} )); then
    echo "  Failed: ${FAILED_VARIANTS[*]}"
fi

echo ""
echo "========================================"
echo "Uploading successful builds to BoringCache"
echo "========================================"

# Upload all successful builds
if (( ${#BUILT_VARIANTS[@]} )); then
  for variant in "${BUILT_VARIANTS[@]}"; do
    echo ""
    echo "Uploading variant: $variant"
    
    # Reconstruct paths for this variant
    RUBY_BASE_DIR="/tmp/ruby-${RUBY_VERSION}-${variant}-${ARCH}"
    
    if command -v boringcache >/dev/null 2>&1; then
        # Generate cache tag without platform suffix (BoringCache handles platform internally)
        if [[ "$variant" == "standard" ]]; then
            cache_tag="ruby-${RUBY_VERSION}"
        else
            cache_tag="ruby-${RUBY_VERSION}-${variant}"
        fi
        
        echo "Uploading $variant variant to BoringCache with tag: $cache_tag"
        echo "SBOM file will be automatically detected and included by CLI"
        echo "DEBUG: BoringCache CLI version: $(boringcache --version 2>/dev/null || echo 'unknown')"
        
        # CLI now automatically detects and includes SBOM files
        # The sbom.json file in RUBY_BASE_DIR will be detected and included
        # Correct format: boringcache save <WORKSPACE> <TAG:PATH>
        SAVE_CMD=(boringcache save)
        if [[ "$BORINGCACHE_USE_CLI_DEFAULT" != true ]]; then
            SAVE_CMD+=("$BORINGCACHE_WORKSPACE")
        fi
        SAVE_CMD+=("$cache_tag:$RUBY_BASE_DIR")

        if "${SAVE_CMD[@]}"; then
            echo "✓ Successfully cached Ruby $RUBY_VERSION ($variant) with SBOM to BoringCache"
        else
            echo "✗ Failed to cache Ruby $RUBY_VERSION ($variant) to BoringCache"
            # Don't fail the entire script for upload errors
        fi
    else
        echo "⚠ BoringCache CLI not available, skipping upload for variant: $variant"
    fi
  done
else
  echo "No successful builds to upload."
fi

# Summary
echo ""
echo "========================================"
echo "Build Summary"
echo "========================================"
echo "Ruby Version: $RUBY_VERSION"
echo "Platform: $PLATFORM-$ARCH"
echo "Requested variants: $VARIANTS"
echo ""

if (( ${#BUILT_VARIANTS[@]} )); then
    echo "✓ Successfully built variants: ${BUILT_VARIANTS[*]}"
fi

if (( ${#FAILED_VARIANTS[@]} )); then
    echo "✗ Failed variants: ${FAILED_VARIANTS[*]}"
    exit 1
fi

if (( ${#BUILT_VARIANTS[@]} == 0 )); then
    echo "✗ No variants were built successfully"
    exit 1
fi

echo "✓ All requested variants built successfully!"
