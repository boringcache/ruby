# BoringCache Ruby Build System
# Provides convenient targets for building and managing Ruby distributions

RUBY_VERSION ?= 3.4.8
PLATFORM ?= $(shell uname -s | tr '[:upper:]' '[:lower:]' | sed 's/darwin/macos/')
ARCH ?= $(shell uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
VARIANTS ?= standard,yjit,jemalloc,jemalloc-yjit
BORINGCACHE_DEFAULT_WORKSPACE ?= ruby/ruby
export BORINGCACHE_DEFAULT_WORKSPACE

# Build directories
BUILD_DIR = /tmp/ruby-build-$(RUBY_VERSION)-$(ARCH)
INSTALL_DIR = /tmp/ruby-$(RUBY_VERSION)-$(ARCH)

.PHONY: help build clean list-cache test-local upload verify

help: ## Show this help message
	@echo "BoringCache Ruby Build System"
	@echo ""
	@echo "Usage: make [target] [RUBY_VERSION=x.x.x] [PLATFORM=platform] [ARCH=arch]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Variables:"
	@echo "  RUBY_VERSION  Ruby version to build (default: $(RUBY_VERSION))"
	@echo "  PLATFORM      Target platform: debian, ubuntu, macos, windows (default: $(PLATFORM))"
	@echo "  ARCH          Target architecture: amd64, arm64 (default: $(ARCH))"
	@echo "  VARIANTS      Ruby variants to build: standard,yjit,jemalloc,jemalloc-yjit (default: $(VARIANTS))"
	@echo "  BORINGCACHE_DEFAULT_WORKSPACE  Workspace used by CLI (default: $(BORINGCACHE_DEFAULT_WORKSPACE))"
	@echo ""
	@echo "Examples:"
	@echo "  make build RUBY_VERSION=3.4.8"
	@echo "  make upload RUBY_VERSION=3.4.8 PLATFORM=ubuntu"
	@echo "  make test-local"

build: ## Build Ruby with all variants locally
	@echo "Building Ruby $(RUBY_VERSION) for $(PLATFORM)-$(ARCH) with variants: $(VARIANTS)..."
	./scripts/build-ruby-variants.sh $(RUBY_VERSION) $(PLATFORM) $(ARCH) $(VARIANTS)
	@echo "✓ Build completed for all variants"

upload: ## Upload built Ruby to BoringCache (requires build first)
	@if [ ! -d "$(INSTALL_DIR)" ]; then \
		echo "Error: No build found at $(INSTALL_DIR). Run 'make build' first."; \
		exit 1; \
	fi
	@echo "Uploading Ruby $(RUBY_VERSION) to $(BORINGCACHE_DEFAULT_WORKSPACE)..."
	boringcache save $(BORINGCACHE_DEFAULT_WORKSPACE) "ruby-$(RUBY_VERSION):$(INSTALL_DIR)" \
		--description "Ruby $(RUBY_VERSION) for $(PLATFORM) $(ARCH)"

list-cache: ## List available Ruby versions in BoringCache
	@echo "Available Ruby versions in $(BORINGCACHE_DEFAULT_WORKSPACE):"
	@boringcache ls $(BORINGCACHE_DEFAULT_WORKSPACE) | grep "^ruby-" | sort -V

clean: ## Clean up build artifacts
	@echo "Cleaning up build artifacts..."
	rm -rf $(BUILD_DIR) $(INSTALL_DIR) /tmp/ruby-download /tmp/ruby-test-*
	@echo "✓ Cleanup completed"

verify: ## Verify a built Ruby installation
	@if [ ! -d "$(INSTALL_DIR)" ]; then \
		echo "Error: No build found at $(INSTALL_DIR). Run 'make build' first."; \
		exit 1; \
	fi
	@echo "Verifying Ruby installation at $(INSTALL_DIR)..."
	@$(INSTALL_DIR)/ruby/bin/ruby --version
	@$(INSTALL_DIR)/ruby/bin/gem --version
	@$(INSTALL_DIR)/ruby/bin/bundle --version
	@echo "✓ Ruby installation verified"

test-local: ## Test local Ruby build
	@echo "Testing local Ruby build..."
	$(MAKE) build
	$(MAKE) verify
	@echo "Testing portability..."
	@TEMP_DIR=$$(mktemp -d) && \
		cp -r $(INSTALL_DIR) "$$TEMP_DIR/" && \
		cd "$$TEMP_DIR" && \
		./ruby-$(RUBY_VERSION)-$(ARCH)/ruby/bin/ruby --version && \
		echo "✓ Portability test passed" && \
		rm -rf "$$TEMP_DIR"


# Dynamic version list from versions.yml
ALL_VERSIONS := $(shell python3 -c "import yaml; print(' '.join(v['version'] for v in yaml.safe_load(open('versions.yml'))['versions']))")

# Development targets
dev-build-all: ## Build all supported versions for current platform
	@for version in $(ALL_VERSIONS); do \
		echo "Building Ruby $$version..."; \
		$(MAKE) build RUBY_VERSION=$$version || exit 1; \
	done

dev-upload-all: ## Upload all built versions (use with caution)
	@for version in $(ALL_VERSIONS); do \
		if [ -d "/tmp/ruby-$$version-$(ARCH)" ]; then \
			echo "Uploading Ruby $$version..."; \
			$(MAKE) upload RUBY_VERSION=$$version; \
		else \
			echo "Skipping Ruby $$version (not built)"; \
		fi \
	done

# CI/CD targets  
ci-build: ## Build and upload all variants (used by CI)
	@echo "CI Build: Ruby $(RUBY_VERSION) for $(PLATFORM)-$(ARCH) with variants: $(VARIANTS)"
	./scripts/build-ruby-variants.sh $(RUBY_VERSION) $(PLATFORM) $(ARCH) $(VARIANTS)

# Information targets
info: ## Show build information
	@echo "Ruby Build Configuration:"
	@echo "  Version: $(RUBY_VERSION)"
	@echo "  Platform: $(PLATFORM)" 
	@echo "  Architecture: $(ARCH)"
	@echo "  Variants: $(VARIANTS)"
	@echo "  Workspace: $(BORINGCACHE_DEFAULT_WORKSPACE)"
	@echo "  Build Dir: $(BUILD_DIR)"
	@echo "  Install Dir: $(INSTALL_DIR)"
	@echo ""
	@echo "Environment:"
	@echo "  BoringCache CLI: $$(command -v boringcache || echo 'not found')"
	@echo "  API Token: $$([ -n "$$BORINGCACHE_API_TOKEN" ] && echo 'set' || echo 'not set')"

versions: ## Show Ruby version configuration
	@echo "Supported Ruby versions (from versions.yml):"
	@python3 -c "import yaml; config=yaml.safe_load(open('versions.yml')); [print(f\"  {v['version']} ({v['status']}, priority: {v['priority']})\") for v in config['versions']]"
