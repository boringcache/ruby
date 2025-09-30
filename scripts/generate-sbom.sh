#!/bin/bash

# Generate SBOM for Ruby installation
# Usage: generate-sbom.sh VARIANT RUBY_PREFIX RUBY_BIN RUBY_VERSION PLATFORM ARCH

set -euo pipefail

VARIANT="$1"
RUBY_PREFIX="$2"
# Default Ruby binary path (platform-specific)
if [[ "$PLATFORM" == "windows" ]]; then
    DEFAULT_RUBY_BIN="$RUBY_PREFIX/bin/ruby.exe"
else
    DEFAULT_RUBY_BIN="$RUBY_PREFIX/bin/ruby"
fi
RUBY_BIN="${3:-$DEFAULT_RUBY_BIN}"
RUBY_VERSION="$4"
PLATFORM="$5"
ARCH="$6"

SBOM_FILE="$RUBY_PREFIX/../sbom.json"

echo "Generating SBOM for Ruby $RUBY_VERSION ($VARIANT variant)..."
echo "Using Ruby binary: $RUBY_BIN"

# Set library path for shared builds
export LD_LIBRARY_PATH="$RUBY_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DYLD_LIBRARY_PATH="$RUBY_PREFIX/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

# Get tool versions
BORINGCACHE_VERSION="unknown"
if command -v boringcache >/dev/null 2>&1; then
    BORINGCACHE_VERSION=$(boringcache --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || BORINGCACHE_VERSION="unknown"
fi

RUBY_BUILD_VERSION="latest"
if command -v ruby-build >/dev/null 2>&1; then
    RUBY_BUILD_VERSION=$(ruby-build --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || RUBY_BUILD_VERSION="latest"
fi

# Create SBOM using the built Ruby
"$RUBY_BIN" -e "
require 'json'
require 'securerandom'

# Get bundled gems info
bundled_gems = []
begin
  gem_specs = Gem::Specification.find_all { |spec| spec.default_gem? }
  gem_specs.each do |spec|
    bundled_gems << {
      'type' => 'library',
      'bom-ref' => \"gem-#{spec.name}\",
      'name' => spec.name,
      'version' => spec.version.to_s,
      'scope' => 'required',
      'description' => spec.summary || 'Ruby bundled gem',
      'purl' => \"pkg:gem/#{spec.name}@#{spec.version}\"
    }
  end
rescue => e
  # Fallback list of common bundled gems
  common_bundled = %w[bundler rake minitest test-unit power_assert net-ftp net-imap net-pop net-smtp matrix prime rexml rss]
  common_bundled.each do |gem_name|
    bundled_gems << {
      'type' => 'library',
      'bom-ref' => \"gem-#{gem_name}\",
      'name' => gem_name,
      'version' => 'bundled',
      'scope' => 'required',
      'description' => 'Ruby bundled gem',
      'purl' => \"pkg:gem/#{gem_name}@bundled\"
    }
  end
end

# Check features
yjit_enabled = '$VARIANT' == 'yjit' || (defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?)
jemalloc_enabled = '$VARIANT' == 'jemalloc' || '$VARIANT'.include?('jemalloc')

# Ruby core component
ruby_component = {
  'type' => 'application',
  'bom-ref' => 'ruby-core',
  'name' => 'ruby',
  'version' => '$RUBY_VERSION',
  'description' => \"Ruby programming language ($VARIANT variant)\",
  'properties' => [
    { 'name' => 'ruby:platform', 'value' => '$PLATFORM' },
    { 'name' => 'ruby:architecture', 'value' => '$ARCH' },
    { 'name' => 'ruby:variant', 'value' => '$VARIANT' },
    { 'name' => 'ruby:yjit_enabled', 'value' => yjit_enabled ? 'yes' : 'no' },
    { 'name' => 'ruby:jemalloc_enabled', 'value' => jemalloc_enabled.to_s },
    { 'name' => 'build:platform', 'value' => RUBY_PLATFORM },
    { 'name' => 'build:compiler', 'value' => 'ruby-build' }
  ]
}

# Generate SBOM
sbom = {
  'bomFormat' => 'CycloneDX',
  'specVersion' => '1.4',
  'serialNumber' => 'urn:uuid:' + SecureRandom.uuid,
  'version' => 1,
  'metadata' => {
    'timestamp' => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
    'tools' => [
      {
        'vendor' => 'rbenv',
        'name' => 'ruby-build',
        'version' => '$RUBY_BUILD_VERSION'
      },
      {
        'vendor' => 'BoringCache',
        'name' => 'boringcache-cli',
        'version' => '$BORINGCACHE_VERSION'
      }
    ],
    'component' => {
      'type' => 'application',
      'name' => \"ruby-$VARIANT\",
      'version' => '$RUBY_VERSION',
      'description' => \"Ruby $RUBY_VERSION ($VARIANT variant) for $PLATFORM-$ARCH\"
    }
  },
  'components' => [ruby_component] + bundled_gems
}

puts JSON.pretty_generate(sbom)
" > "$SBOM_FILE"

if [[ -f "$SBOM_FILE" ]]; then
    echo "✓ SBOM generated: $SBOM_FILE"
else
    echo "✗ Failed to generate SBOM"
    exit 1
fi