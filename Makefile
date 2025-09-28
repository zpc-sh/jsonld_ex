# BUILD: Advanced Makefile for JsonldEx development

.PHONY: help clean dev prod test bench ci pgo install format lint docs release
.PHONY: install-cross verify-docker
.PHONY: gh-release gh-precompiled gh-check-releases gh-status gh-fix-missing gh-setup
.PHONY: install-zigbuild
.PHONY: preflight-check
.PHONY: version-patch version-minor version-major hex-build hex-publish hex-docs hex-retire
.PHONY: release-patch release-minor release-major release-full hex-check hex-auth
.PHONY: version-current version-check changelog-update release-status pre-release-check

# Default target
.DEFAULT_GOAL := help

# BUILD: Host detection and default env for Apple Silicon
HOST_OS := $(shell uname -s)
HOST_ARCH := $(shell uname -m)

# On Apple Silicon/aarch64 hosts, default Docker to run amd64 images (Rosetta)
ifeq ($(HOST_ARCH),arm64)
export DOCKER_DEFAULT_PLATFORM ?= linux/amd64
endif
ifeq ($(HOST_ARCH),aarch64)
export DOCKER_DEFAULT_PLATFORM ?= linux/amd64
endif

# Default cross to use Docker when present
export CROSS_CONTAINER_ENGINE ?= docker
# Keep cross image platform aligned with Docker default (can be overridden)
export CROSS_IMAGE_PLATFORM ?= $(DOCKER_DEFAULT_PLATFORM)

# BUILD: Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# BUILD: Print help
help: ## Show this help message
	@echo "JsonldEx Advanced Build System"
	@echo ""
	@echo "$(BLUE)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-12s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BLUE)Examples:$(NC)"
	@echo "  make dev         # Fast development build"
	@echo "  make prod        # Production build with full optimizations"
	@echo "  make bench       # Run comprehensive benchmarks"
	@echo "  make ci          # Full CI pipeline"
	@echo "  make macos       # Force local build on macOS (fixes LTO errors)"
	@echo ""
	@echo "$(BLUE)GitHub Releases (fix rustler_precompiled):$(NC)"
	@echo "  make gh-setup      # Setup GitHub CLI and authenticate"
	@echo "  make gh-status     # Check if current version has precompiled NIFs"
	@echo "  make gh-fix-missing # Auto-fix missing precompiled artifacts"
	@echo "  make gh-release    # Create new GitHub release with precompiled NIFs"
	@echo ""
	@echo "$(BLUE)Release Management:$(NC)"
	@echo "  make version-patch   # Increment patch version (0.4.2 -> 0.4.3)"
	@echo "  make version-minor   # Increment minor version (0.4.2 -> 0.5.0)"
	@echo "  make version-major   # Increment major version (0.4.2 -> 1.0.0)"
	@echo ""
	@echo "$(BLUE)Hex.pm Publishing:$(NC)"
	@echo "  make hex-build       # Build hex package"
	@echo "  make hex-publish     # Publish to hex.pm (requires auth)"
	@echo "  make hex-docs        # Publish documentation to hex.pm"
	@echo "  make hex-retire      # Retire a published version"
	@echo "  make hex-auth        # Authenticate with hex.pm"
	@echo "  make hex-check       # Check hex.pm authentication status"
	@echo ""
	@echo "$(BLUE)Complete Release Workflows:$(NC)"
	@echo "  make release-patch   # Version bump + GitHub release + hex publish (patch)"
	@echo "  make release-minor   # Version bump + GitHub release + hex publish (minor)"  
	@echo "  make release-major   # Version bump + GitHub release + hex publish (major)"
	@echo "  make release-full    # Interactive release workflow with all options"
	@echo ""
	@echo "$(BLUE)Release Utilities:$(NC)"
	@echo "  make version-current # Show current version"
	@echo "  make version-check   # Check version consistency across files"
	@echo "  make changelog-update # Update CHANGELOG.md with new version"
	@echo "  make release-status  # Check release readiness"
	@echo "  make pre-release-check # Run all pre-release checks"

# BUILD: Clean all artifacts
clean: ## Clean all build artifacts
	@echo "$(BLUE)[BUILD]$(NC) Cleaning all build artifacts..."
	./scripts/build.sh clean

# BUILD: Development build
dev: ## Fast development build
	@echo "$(BLUE)[BUILD]$(NC) Building for development..."
	./scripts/build.sh dev

# BUILD: Production build
prod: ## Production build with full optimizations
	@echo "$(BLUE)[BUILD]$(NC) Building for production..."
	./scripts/build.sh prod

# BUILD: Test with coverage
test: ## Run tests with coverage
	@echo "$(BLUE)[BUILD]$(NC) Running tests..."
	./scripts/build.sh test

# BUILD: macOS local build (workaround for LTO issues)
macos: ## Force local build on macOS (fixes LTO compiler errors)
	@echo "$(BLUE)[BUILD]$(NC) Building locally on macOS..."
	JSONLD_NIF_FORCE_BUILD=1 mix compile

# BUILD: Comprehensive benchmarks
bench: ## Run comprehensive benchmarks
	@echo "$(BLUE)[BUILD]$(NC) Running benchmarks..."
	./scripts/build.sh bench

# BUILD: CI pipeline
ci: ## Run full CI pipeline
	@echo "$(BLUE)[BUILD]$(NC) Running CI pipeline..."
	./scripts/build.sh ci

# BUILD: Profile-guided optimization
pgo: ## Build with Profile-Guided Optimization
	@echo "$(BLUE)[BUILD]$(NC) Building with PGO..."
	./scripts/build.sh pgo

# BUILD: Install dependencies
install: ## Install all dependencies
	@echo "$(BLUE)[BUILD]$(NC) Installing dependencies..."
	mix deps.get
	cd native/jsonld_nif && cargo fetch

# BUILD: Install cross and verify Docker
install-cross: ## Install the cross tool (containerized builds) and verify Docker
	@echo "$(BLUE)[BUILD]$(NC) Installing cross (containerized Rust builds)..."
	cargo install cross || true
	@echo "$(BLUE)[BUILD]$(NC) Verifying Docker connectivity..."
	@docker info >/dev/null 2>&1 \
		&& echo "$(GREEN)[OK]$(NC) Docker is available" \
		|| (echo "$(YELLOW)[WARN]$(NC) Docker not available. Start Docker/Colima and retry." && exit 1)

verify-docker: ## Check Docker/Colima availability for cross
	@docker info >/dev/null 2>&1 \
		&& echo "$(GREEN)[OK]$(NC) Docker is available" \
		|| (echo "$(YELLOW)[WARN]$(NC) Docker not available. Start Docker/Colima and retry." && exit 1)

# BUILD: Install cargo-zigbuild and verify zig (fallback path when Docker is unavailable)
install-zigbuild: ## Install cargo-zigbuild and verify zig is installed
	@echo "$(BLUE)[BUILD]$(NC) Installing cargo-zigbuild..."
	cargo install cargo-zigbuild || true
	@echo "$(BLUE)[BUILD]$(NC) Checking for zig compiler..."
	@command -v zig >/dev/null 2>&1 \
		&& zig version \
		|| (echo "$(YELLOW)[WARN]$(NC) 'zig' not found. Install zig (e.g., 'brew install zig' on macOS or 'sudo apt-get install -y zig' on Debian/Ubuntu) and re-run." && exit 1)

# BUILD: Format code
format: ## Format Elixir and Rust code
	@echo "$(BLUE)[BUILD]$(NC) Formatting code with .formatter.exs..."
	mix format
	cd native/jsonld_nif && cargo fmt

# BUILD: Lint code
lint: ## Lint Elixir and Rust code
	@echo "$(BLUE)[BUILD]$(NC) Linting code..."
	mix format --check-formatted
	JSONLD_NIF_FORCE_BUILD=1 mix credo --strict
	cd native/jsonld_nif && cargo clippy -- -D warnings

# BUILD: Generate documentation
docs: ## Generate documentation
	@echo "$(BLUE)[BUILD]$(NC) Generating documentation..."
	mix docs

# BUILD: Release build and packaging
release: prod docs ## Create a release package
	@echo "$(BLUE)[BUILD]$(NC) Creating release package..."
	mix hex.build

# RELEASE: Version management
version-patch: ## Increment patch version (0.4.2 -> 0.4.3)
	@echo "$(BLUE)[RELEASE]$(NC) Incrementing patch version..."
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	IFS='.' read -r major minor patch <<< "$$CURRENT_VERSION"; \
	NEW_PATCH=$$((patch + 1)); \
	NEW_VERSION="$$major.$$minor.$$NEW_PATCH"; \
	echo "$(GREEN)Updating version:$(NC) $$CURRENT_VERSION -> $$NEW_VERSION"; \
	sed -i.bak "s/version: \"$$CURRENT_VERSION\",/version: \"$$NEW_VERSION\",/" mix.exs && rm mix.exs.bak; \
	echo "$(GREEN)✓$(NC) Version updated in mix.exs"; \
	echo "$(BLUE)Next steps:$(NC)"; \
	echo "  1. Update CHANGELOG.md: make changelog-update"; \
	echo "  2. Run pre-release checks: make pre-release-check"; \
	echo "  3. Create release: make release-patch"

version-minor: ## Increment minor version (0.4.2 -> 0.5.0)
	@echo "$(BLUE)[RELEASE]$(NC) Incrementing minor version..."
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	IFS='.' read -r major minor patch <<< "$$CURRENT_VERSION"; \
	NEW_MINOR=$$((minor + 1)); \
	NEW_VERSION="$$major.$$NEW_MINOR.0"; \
	echo "$(GREEN)Updating version:$(NC) $$CURRENT_VERSION -> $$NEW_VERSION"; \
	sed -i.bak "s/version: \"$$CURRENT_VERSION\",/version: \"$$NEW_VERSION\",/" mix.exs && rm mix.exs.bak; \
	echo "$(GREEN)✓$(NC) Version updated in mix.exs"; \
	echo "$(BLUE)Next steps:$(NC)"; \
	echo "  1. Update CHANGELOG.md: make changelog-update"; \
	echo "  2. Run pre-release checks: make pre-release-check"; \
	echo "  3. Create release: make release-minor"

version-major: ## Increment major version (0.4.2 -> 1.0.0)
	@echo "$(BLUE)[RELEASE]$(NC) Incrementing major version..."
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	IFS='.' read -r major minor patch <<< "$$CURRENT_VERSION"; \
	NEW_MAJOR=$$((major + 1)); \
	NEW_VERSION="$$NEW_MAJOR.0.0"; \
	echo "$(GREEN)Updating version:$(NC) $$CURRENT_VERSION -> $$NEW_VERSION"; \
	sed -i.bak "s/version: \"$$CURRENT_VERSION\",/version: \"$$NEW_VERSION\",/" mix.exs && rm mix.exs.bak; \
	echo "$(GREEN)✓$(NC) Version updated in mix.exs"; \
	echo "$(BLUE)Next steps:$(NC)"; \
	echo "  1. Update CHANGELOG.md: make changelog-update"; \
	echo "  2. Run pre-release checks: make pre-release-check"; \
	echo "  3. Create release: make release-major"

# HEX: Package management
hex-build: clean prod docs ## Build hex package
	@echo "$(BLUE)[HEX]$(NC) Building hex package..."
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(GREEN)Building version:$(NC) $$CURRENT_VERSION"; \
	mix hex.build
	@echo "$(GREEN)✓$(NC) Package built successfully"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Review the package: tar -tf jsonld_ex-*.tar"
	@echo "  2. Test locally: mix hex.build --unpack"
	@echo "  3. Publish: make hex-publish"

hex-publish: hex-build ## Publish package to hex.pm
	@echo "$(BLUE)[HEX]$(NC) Publishing to hex.pm..."
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(YELLOW)[CONFIRM]$(NC) About to publish version $$CURRENT_VERSION to hex.pm"; \
	echo "$(YELLOW)This action cannot be undone. Continue? [y/N]$(NC)"; \
	read -r CONFIRM </dev/tty; \
	if [ "$$CONFIRM" = "y" ] || [ "$$CONFIRM" = "Y" ]; then \
		echo "$(BLUE)[PUBLISH]$(NC) Publishing..."; \
		mix hex.publish --yes || (echo "$(YELLOW)[ERROR]$(NC) Publish failed. Make sure you're authenticated: mix hex.user auth"; exit 1); \
		echo "$(GREEN)✓$(NC) Published successfully!"; \
		echo "$(BLUE)Package URL:$(NC) https://hex.pm/packages/jsonld_ex"; \
	else \
		echo "$(YELLOW)[CANCELLED]$(NC) Publish cancelled"; \
	fi

hex-docs: docs ## Publish documentation to hex.pm
	@echo "$(BLUE)[HEX]$(NC) Publishing documentation to hex.pm..."
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(GREEN)Publishing docs for version:$(NC) $$CURRENT_VERSION"; \
	mix hex.publish docs --yes || (echo "$(YELLOW)[ERROR]$(NC) Docs publish failed. Make sure you're authenticated: mix hex.user auth"; exit 1)
	@echo "$(GREEN)✓$(NC) Documentation published!"
	@echo "$(BLUE)Docs URL:$(NC) https://hexdocs.pm/jsonld_ex/"

hex-retire: ## Retire a published version from hex.pm
	@echo "$(BLUE)[HEX]$(NC) Retiring a version from hex.pm..."
	@echo "$(YELLOW)[INPUT]$(NC) Enter version to retire (e.g., 0.4.1):"
	@read -r VERSION </dev/tty; \
	if [ -z "$$VERSION" ]; then \
		echo "$(YELLOW)[ERROR]$(NC) Version cannot be empty"; \
		exit 1; \
	fi; \
	echo "$(YELLOW)[INPUT]$(NC) Enter retirement reason:"; \
	echo "  1. security     - Security issue"; \
	echo "  2. deprecated   - Deprecated"; \
	echo "  3. invalid      - Invalid release"; \
	echo "  4. other        - Other"; \
	read -r REASON_NUM </dev/tty; \
	case "$$REASON_NUM" in \
		"1") REASON="security" ;; \
		"2") REASON="deprecated" ;; \
		"3") REASON="invalid" ;; \
		"4") REASON="other" ;; \
		*) echo "$(YELLOW)[ERROR]$(NC) Invalid choice"; exit 1 ;; \
	esac; \
	echo "$(YELLOW)[CONFIRM]$(NC) Retire version $$VERSION with reason '$$REASON'? [y/N]"; \
	read -r CONFIRM </dev/tty; \
	if [ "$$CONFIRM" = "y" ] || [ "$$CONFIRM" = "Y" ]; then \
		echo "$(BLUE)[RETIRE]$(NC) Retiring version $$VERSION..."; \
		mix hex.retire jsonld_ex $$VERSION --reason=$$REASON --yes; \
		echo "$(GREEN)✓$(NC) Version $$VERSION retired"; \
	else \
		echo "$(YELLOW)[CANCELLED]$(NC) Retirement cancelled"; \
	fi

hex-auth: ## Authenticate with hex.pm
	@echo "$(BLUE)[HEX]$(NC) Authenticating with hex.pm..."
	@if mix hex.user whoami >/dev/null 2>&1; then \
		echo "$(GREEN)✓$(NC) Already authenticated with hex.pm"; \
		mix hex.user whoami; \
	else \
		echo "$(YELLOW)[AUTH]$(NC) Please authenticate with hex.pm..."; \
		mix hex.user auth; \
	fi

hex-check: ## Check hex.pm authentication status
	@echo "$(BLUE)[HEX]$(NC) Checking hex.pm authentication..."
	@if mix hex.user whoami >/dev/null 2>&1; then \
		echo "$(GREEN)✓$(NC) Authenticated with hex.pm as:"; \
		mix hex.user whoami; \
	else \
		echo "$(YELLOW)[NOT AUTH]$(NC) Not authenticated with hex.pm"; \
		echo "$(BLUE)Run:$(NC) make hex-auth"; \
	fi

# RELEASE: Complete release workflows
release-patch: ## Complete patch release workflow (version bump + GitHub release + hex publish)
	@echo "$(BLUE)[RELEASE]$(NC) Starting complete patch release workflow..."
	@make version-patch
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(YELLOW)[CONFIRM]$(NC) About to create complete release for version $$CURRENT_VERSION"; \
	echo "This will:"; \
	echo "  1. Create GitHub release with precompiled NIFs"; \
	echo "  2. Publish package to hex.pm"; \
	echo "  3. Publish documentation"; \
	echo "$(YELLOW)Continue? [y/N]$(NC)"; \
	read -r CONFIRM </dev/tty; \
	if [ "$$CONFIRM" = "y" ] || [ "$$CONFIRM" = "Y" ]; then \
		echo "$(BLUE)[STEP 1/3]$(NC) Creating GitHub release..."; \
		echo "v$$CURRENT_VERSION" | gh workflow run release-precompiled.yml --stdin -f tag_name=v$$CURRENT_VERSION -f prerelease=false || echo "$(YELLOW)[WARN]$(NC) GitHub release may have failed"; \
		echo "$(BLUE)[STEP 2/3]$(NC) Publishing to hex.pm..."; \
		make hex-publish; \
		echo "$(BLUE)[STEP 3/3]$(NC) Publishing documentation..."; \
		make hex-docs; \
		echo "$(GREEN)✓$(NC) Complete patch release workflow finished!"; \
		echo "$(BLUE)Released version:$(NC) $$CURRENT_VERSION"; \
	else \
		echo "$(YELLOW)[CANCELLED]$(NC) Release workflow cancelled"; \
	fi

release-minor: ## Complete minor release workflow (version bump + GitHub release + hex publish)
	@echo "$(BLUE)[RELEASE]$(NC) Starting complete minor release workflow..."
	@make version-minor
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(YELLOW)[CONFIRM]$(NC) About to create complete release for version $$CURRENT_VERSION"; \
	echo "This will:"; \
	echo "  1. Create GitHub release with precompiled NIFs"; \
	echo "  2. Publish package to hex.pm"; \
	echo "  3. Publish documentation"; \
	echo "$(YELLOW)Continue? [y/N]$(NC)"; \
	read -r CONFIRM </dev/tty; \
	if [ "$$CONFIRM" = "y" ] || [ "$$CONFIRM" = "Y" ]; then \
		echo "$(BLUE)[STEP 1/3]$(NC) Creating GitHub release..."; \
		echo "v$$CURRENT_VERSION" | gh workflow run release-precompiled.yml --stdin -f tag_name=v$$CURRENT_VERSION -f prerelease=false || echo "$(YELLOW)[WARN]$(NC) GitHub release may have failed"; \
		echo "$(BLUE)[STEP 2/3]$(NC) Publishing to hex.pm..."; \
		make hex-publish; \
		echo "$(BLUE)[STEP 3/3]$(NC) Publishing documentation..."; \
		make hex-docs; \
		echo "$(GREEN)✓$(NC) Complete minor release workflow finished!"; \
		echo "$(BLUE)Released version:$(NC) $$CURRENT_VERSION"; \
	else \
		echo "$(YELLOW)[CANCELLED]$(NC) Release workflow cancelled"; \
	fi

release-major: ## Complete major release workflow (version bump + GitHub release + hex publish)
	@echo "$(BLUE)[RELEASE]$(NC) Starting complete major release workflow..."
	@make version-major
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(YELLOW)[CONFIRM]$(NC) About to create complete release for version $$CURRENT_VERSION"; \
	echo "This will:"; \
	echo "  1. Create GitHub release with precompiled NIFs"; \
	echo "  2. Publish package to hex.pm"; \
	echo "  3. Publish documentation"; \
	echo "$(YELLOW)Continue? [y/N]$(NC)"; \
	read -r CONFIRM </dev/tty; \
	if [ "$$CONFIRM" = "y" ] || [ "$$CONFIRM" = "Y" ]; then \
		echo "$(BLUE)[STEP 1/3]$(NC) Creating GitHub release..."; \
		echo "v$$CURRENT_VERSION" | gh workflow run release-precompiled.yml --stdin -f tag_name=v$$CURRENT_VERSION -f prerelease=false || echo "$(YELLOW)[WARN]$(NC) GitHub release may have failed"; \
		echo "$(BLUE)[STEP 2/3]$(NC) Publishing to hex.pm..."; \
		make hex-publish; \
		echo "$(BLUE)[STEP 3/3]$(NC) Publishing documentation..."; \
		make hex-docs; \
		echo "$(GREEN)✓$(NC) Complete major release workflow finished!"; \
		echo "$(BLUE)Released version:$(NC) $$CURRENT_VERSION"; \
	else \
		echo "$(YELLOW)[CANCELLED]$(NC) Release workflow cancelled"; \
	fi

release-full: ## Interactive release workflow with all options
	@echo "$(BLUE)[RELEASE]$(NC) Interactive release workflow"
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(GREEN)Current version:$(NC) $$CURRENT_VERSION"; \
	echo ""; \
	echo "$(BLUE)Release type:$(NC)"; \
	echo "  1. Patch ($$CURRENT_VERSION -> $$(echo $$CURRENT_VERSION | awk -F. '{print $$1"."$$2"."($$3+1)}'))"; \
	echo "  2. Minor ($$CURRENT_VERSION -> $$(echo $$CURRENT_VERSION | awk -F. '{print $$1"."($$2+1)".0"}'))"; \
	echo "  3. Major ($$CURRENT_VERSION -> $$(echo $$CURRENT_VERSION | awk -F. '{print ($$1+1)".0.0"}'))"; \
	echo "  4. Custom version"; \
	echo "  5. Skip version bump"; \
	read -r RELEASE_TYPE </dev/tty; \
	case "$$RELEASE_TYPE" in \
		"1") make version-patch ;; \
		"2") make version-minor ;; \
		"3") make version-major ;; \
		"4") echo "$(YELLOW)[INPUT]$(NC) Enter new version (e.g., 1.0.0-rc.1):"; \
		   read -r NEW_VERSION </dev/tty; \
		   sed -i.bak "s/version: \"$$CURRENT_VERSION\",/version: \"$$NEW_VERSION\",/" mix.exs && rm mix.exs.bak; \
		   echo "$(GREEN)✓$(NC) Version set to $$NEW_VERSION" ;; \
		"5") echo "$(BLUE)Skipping version bump$(NC)" ;; \
		*) echo "$(YELLOW)[ERROR]$(NC) Invalid choice: '$$RELEASE_TYPE'"; exit 1 ;; \
	esac; \
	FINAL_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo ""; \
	echo "$(BLUE)Release options:$(NC)"; \
	echo "  1. GitHub release only"; \
	echo "  2. Hex.pm publish only"; \
	echo "  3. Full release (GitHub + Hex.pm + Docs)"; \
	read -r RELEASE_OPTION </dev/tty; \
	echo "$(YELLOW)[CONFIRM]$(NC) Releasing version $$FINAL_VERSION with selected options. Continue? [y/N]"; \
	read -r CONFIRM </dev/tty; \
	if [ "$$CONFIRM" = "y" ] || [ "$$CONFIRM" = "Y" ]; then \
		case "$$RELEASE_OPTION" in \
			"1") echo "$(BLUE)Creating GitHub release...$(NC)"; \
			   echo "v$$FINAL_VERSION" | gh workflow run release-precompiled.yml --stdin -f tag_name=v$$FINAL_VERSION -f prerelease=false ;; \
			"2") echo "$(BLUE)Publishing to hex.pm...$(NC)"; \
			   make hex-publish ;; \
			"3") echo "$(BLUE)Full release workflow...$(NC)"; \
			   echo "v$$FINAL_VERSION" | gh workflow run release-precompiled.yml --stdin -f tag_name=v$$FINAL_VERSION -f prerelease=false; \
			   make hex-publish; \
			   make hex-docs ;; \
			*) echo "$(YELLOW)[ERROR]$(NC) Invalid choice: '$$RELEASE_OPTION'"; exit 1 ;; \
		esac; \
		echo "$(GREEN)✓$(NC) Release workflow completed for version $$FINAL_VERSION!"; \
	else \
		echo "$(YELLOW)[CANCELLED]$(NC) Release cancelled"; \
	fi

# RELEASE: Utility commands
version-current: ## Show current version
	@echo "$(BLUE)[VERSION]$(NC) Current version information:"
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(GREEN)Version:$(NC) $$CURRENT_VERSION"; \
	echo "$(GREEN)Git tag:$(NC) v$$CURRENT_VERSION"; \
	echo "$(GREEN)Hex.pm URL:$(NC) https://hex.pm/packages/jsonld_ex/$$CURRENT_VERSION"

version-check: ## Check version consistency across files
	@echo "$(BLUE)[VERSION]$(NC) Checking version consistency..."
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(GREEN)mix.exs:$(NC) $$CURRENT_VERSION"; \
	if [ -f "README.md" ]; then \
		README_VERSION=$$(grep -o '{:jsonld_ex, "~> [0-9][^"]*"' README.md | head -1 | sed 's/.*"~> \([^"]*\)".*/\1/' || echo "not found"); \
		echo "$(GREEN)README.md:$(NC) $$README_VERSION"; \
	fi; \
	if [ -f "CHANGELOG.md" ]; then \
		CHANGELOG_VERSION=$$(grep -E "^## \[?[0-9]" CHANGELOG.md | head -1 | sed 's/.*\[\?\([0-9][^]]*\).*/\1/' || echo "not found"); \
		echo "$(GREEN)CHANGELOG.md:$(NC) $$CHANGELOG_VERSION"; \
	fi; \
	echo "$(BLUE)Checking Git tags...$(NC)"; \
	if git tag -l "v$$CURRENT_VERSION" | grep -q "v$$CURRENT_VERSION"; then \
		echo "$(GREEN)Git tag v$$CURRENT_VERSION:$(NC) exists"; \
	else \
		echo "$(YELLOW)Git tag v$$CURRENT_VERSION:$(NC) missing"; \
	fi

changelog-update: ## Update CHANGELOG.md with new version
	@echo "$(BLUE)[CHANGELOG]$(NC) Updating CHANGELOG.md..."
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	if [ ! -f "CHANGELOG.md" ]; then \
		echo "$(YELLOW)[CREATE]$(NC) Creating CHANGELOG.md"; \
		echo "# Changelog" > CHANGELOG.md; \
		echo "" >> CHANGELOG.md; \
		echo "All notable changes to this project will be documented in this file." >> CHANGELOG.md; \
		echo "" >> CHANGELOG.md; \
		echo "The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)," >> CHANGELOG.md; \
		echo "and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)." >> CHANGELOG.md; \
		echo "" >> CHANGELOG.md; \
	fi; \
	echo "$(BLUE)Adding entry for version $$CURRENT_VERSION...$(NC)"; \
	DATE=$$(date +"%Y-%m-%d"); \
	if ! grep -q "## \[$$CURRENT_VERSION\]" CHANGELOG.md; then \
		cp CHANGELOG.md CHANGELOG.md.bak; \
		head -6 CHANGELOG.md.bak > CHANGELOG.md; \
		echo "" >> CHANGELOG.md; \
		echo "## [$$CURRENT_VERSION] - $$DATE" >> CHANGELOG.md; \
		echo "" >> CHANGELOG.md; \
		echo "### Added" >> CHANGELOG.md; \
		echo "- " >> CHANGELOG.md; \
		echo "" >> CHANGELOG.md; \
		echo "### Changed" >> CHANGELOG.md; \
		echo "- " >> CHANGELOG.md; \
		echo "" >> CHANGELOG.md; \
		echo "### Fixed" >> CHANGELOG.md; \
		echo "- " >> CHANGELOG.md; \
		echo "" >> CHANGELOG.md; \
		tail -n +7 CHANGELOG.md.bak >> CHANGELOG.md; \
		rm CHANGELOG.md.bak; \
		echo "$(GREEN)✓$(NC) Added entry for version $$CURRENT_VERSION"; \
		echo "$(BLUE)Please edit CHANGELOG.md to add release notes$(NC)"; \
	else \
		echo "$(YELLOW)Entry for version $$CURRENT_VERSION already exists$(NC)"; \
	fi

release-status: ## Check release readiness
	@echo "$(BLUE)[RELEASE]$(NC) Checking release readiness..."
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(GREEN)Version:$(NC) $$CURRENT_VERSION"; \
	echo ""; \
	echo "$(BLUE)Checklist:$(NC)"; \
	if [ -f "CHANGELOG.md" ] && grep -q "## \[$$CURRENT_VERSION\]" CHANGELOG.md; then \
		echo "$(GREEN)✓$(NC) CHANGELOG.md updated"; \
	else \
		echo "$(YELLOW)✗$(NC) CHANGELOG.md needs update (run: make changelog-update)"; \
	fi; \
	if git status --porcelain | grep -q .; then \
		echo "$(YELLOW)✗$(NC) Uncommitted changes present"; \
		git status --short; \
	else \
		echo "$(GREEN)✓$(NC) Working directory clean"; \
	fi; \
	if mix hex.user whoami >/dev/null 2>&1; then \
		echo "$(GREEN)✓$(NC) Hex.pm authentication configured"; \
	else \
		echo "$(YELLOW)✗$(NC) Hex.pm authentication needed (run: make hex-auth)"; \
	fi; \
	if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then \
		echo "$(GREEN)✓$(NC) GitHub CLI authenticated"; \
	else \
		echo "$(YELLOW)✗$(NC) GitHub CLI needed (run: make gh-setup)"; \
	fi; \
	if git tag -l "v$$CURRENT_VERSION" | grep -q "v$$CURRENT_VERSION"; then \
		echo "$(YELLOW)!$(NC) Git tag v$$CURRENT_VERSION already exists"; \
	else \
		echo "$(GREEN)✓$(NC) Git tag v$$CURRENT_VERSION available"; \
	fi

pre-release-check: clean ## Run all pre-release checks
	@echo "$(BLUE)[PRE-RELEASE]$(NC) Running comprehensive pre-release checks..."
	@echo "$(BLUE)[1/6]$(NC) Checking version consistency..."
	@make version-check
	@echo ""
	@echo "$(BLUE)[2/6]$(NC) Running tests with coverage..."
	@make test
	@echo ""
	@echo "$(BLUE)[3/6]$(NC) Checking code format and linting..."
	@make format lint
	@echo ""
	@echo "$(BLUE)[4/6]$(NC) Building documentation..."
	@make docs
	@echo ""
	@echo "$(BLUE)[5/6]$(NC) Building hex package..."
	@make hex-build
	@echo ""
	@echo "$(BLUE)[6/6]$(NC) Checking release status..."
	@make release-status
	@echo ""
	@echo "$(GREEN)✓$(NC) Pre-release checks completed!"
	@echo "$(BLUE)Ready for release:$(NC) make release-patch|release-minor|release-major"

# BUILD: GitHub workflow triggers
gh-release: ## Trigger GitHub release workflow (creates new release with precompiled NIFs)
	@echo "$(BLUE)[BUILD]$(NC) Triggering GitHub release workflow..."
	@if ! command -v gh >/dev/null 2>&1; then \
		echo "$(YELLOW)[ERROR]$(NC) GitHub CLI (gh) not found. Install with: brew install gh"; \
		exit 1; \
	fi
	@echo "$(YELLOW)[INPUT]$(NC) Enter new version tag (e.g., v0.4.3):"
	@read -r VERSION; \
	if [ -z "$$VERSION" ]; then \
		echo "$(YELLOW)[ERROR]$(NC) Version tag cannot be empty"; \
		exit 1; \
	fi; \
	echo "$(BLUE)[BUILD]$(NC) Creating release $$VERSION and triggering precompiled build..."; \
	gh workflow run release-precompiled.yml \
		-f tag_name="$$VERSION" \
		-f prerelease=false || \
	(echo "$(YELLOW)[ERROR]$(NC) Failed to trigger workflow. Make sure you're authenticated: gh auth login"; exit 1)

gh-precompiled: ## Trigger precompiled build workflow for existing tag
	@echo "$(BLUE)[BUILD]$(NC) Triggering precompiled build workflow..."
	@if ! command -v gh >/dev/null 2>&1; then \
		echo "$(YELLOW)[ERROR]$(NC) GitHub CLI (gh) not found. Install with: brew install gh"; \
		exit 1; \
	fi
	@echo "$(YELLOW)[INPUT]$(NC) Enter existing tag to build precompiled NIFs for (e.g., v0.4.2):"
	@read -r VERSION; \
	if [ -z "$$VERSION" ]; then \
		echo "$(YELLOW)[ERROR]$(NC) Version tag cannot be empty"; \
		exit 1; \
	fi; \
	echo "$(BLUE)[BUILD]$(NC) Triggering precompiled build for $$VERSION..."; \
	gh workflow run release-precompiled.yml \
		-f tag_name="$$VERSION" \
		-f prerelease=false || \
	(echo "$(YELLOW)[ERROR]$(NC) Failed to trigger workflow. Make sure you're authenticated: gh auth login"; exit 1)

gh-check-releases: ## Check recent GitHub releases and workflow runs
	@echo "$(BLUE)[BUILD]$(NC) Checking recent releases and workflows..."
	@if ! command -v gh >/dev/null 2>&1; then \
		echo "$(YELLOW)[ERROR]$(NC) GitHub CLI (gh) not found. Install with: brew install gh"; \
		exit 1; \
	fi
	@echo ""
	@echo "$(GREEN)Recent Releases:$(NC)"
	@gh release list --limit 5 || echo "$(YELLOW)[WARN]$(NC) Could not fetch releases"
	@echo ""
	@echo "$(GREEN)Recent Workflow Runs:$(NC)"
	@gh run list --workflow=release-precompiled.yml --limit 5 || echo "$(YELLOW)[WARN]$(NC) Could not fetch workflow runs"
	@echo ""
	@echo "$(BLUE)Tip:$(NC) Use 'gh release view <tag>' to see assets for a specific release"

gh-status: ## Check if current version has precompiled macOS artifacts
	@echo "$(BLUE)[BUILD]$(NC) Checking precompiled artifact status..."
	@if ! command -v gh >/dev/null 2>&1; then \
		echo "$(YELLOW)[ERROR]$(NC) GitHub CLI (gh) not found. Install with: brew install gh"; \
		exit 1; \
	fi
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(GREEN)Current version:$(NC) $$CURRENT_VERSION"; \
	echo "$(BLUE)[BUILD]$(NC) Checking release v$$CURRENT_VERSION..."; \
	if gh release view "v$$CURRENT_VERSION" >/dev/null 2>&1; then \
		echo "$(GREEN)✓$(NC) Release v$$CURRENT_VERSION exists"; \
		echo "$(BLUE)Assets:$(NC)"; \
		gh release view "v$$CURRENT_VERSION" --json assets --jq '.assets[].name' | grep -E '\.(tar\.gz|so)$$' || echo "$(YELLOW)[WARN]$(NC) No precompiled assets found"; \
		if gh release view "v$$CURRENT_VERSION" --json assets --jq '.assets[].name' | grep -q 'aarch64-apple-darwin'; then \
			echo "$(GREEN)✓$(NC) macOS Apple Silicon artifacts available"; \
		else \
			echo "$(YELLOW)[MISSING]$(NC) macOS Apple Silicon artifacts missing"; \
		fi; \
	else \
		echo "$(YELLOW)[MISSING]$(NC) Release v$$CURRENT_VERSION does not exist"; \
		echo "$(BLUE)Suggestion:$(NC) Run 'make gh-release' to create it"; \
	fi

gh-fix-missing: ## Automatically fix missing precompiled artifacts for current version
	@echo "$(BLUE)[BUILD]$(NC) Checking and fixing missing precompiled artifacts..."
	@if ! command -v gh >/dev/null 2>&1; then \
		echo "$(YELLOW)[ERROR]$(NC) GitHub CLI (gh) not found. Install with: brew install gh"; \
		exit 1; \
	fi
	@CURRENT_VERSION=$$(grep 'version:' mix.exs | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "$(GREEN)Current version:$(NC) $$CURRENT_VERSION"; \
	if gh release view "v$$CURRENT_VERSION" >/dev/null 2>&1; then \
		echo "$(GREEN)✓$(NC) Release v$$CURRENT_VERSION exists"; \
		if ! gh release view "v$$CURRENT_VERSION" --json assets --jq '.assets[].name' | grep -q 'apple-darwin'; then \
			echo "$(YELLOW)[FIXING]$(NC) Missing macOS artifacts, triggering rebuild..."; \
			gh workflow run release-precompiled.yml \
				-f tag_name="v$$CURRENT_VERSION" \
				-f prerelease=false; \
			echo "$(GREEN)✓$(NC) Rebuild triggered. Check status with 'make gh-check-releases'"; \
		else \
			echo "$(GREEN)✓$(NC) All macOS artifacts already available"; \
		fi; \
	else \
		echo "$(YELLOW)[CREATING]$(NC) Release v$$CURRENT_VERSION does not exist, creating it..."; \
		gh workflow run release-precompiled.yml \
			-f tag_name="v$$CURRENT_VERSION" \
			-f prerelease=false; \
		echo "$(GREEN)✓$(NC) Release creation triggered. Check status with 'make gh-check-releases'"; \
	fi

gh-setup: ## Setup GitHub CLI and authenticate
	@echo "$(BLUE)[BUILD]$(NC) Setting up GitHub CLI..."
	@if command -v gh >/dev/null 2>&1; then \
		echo "$(GREEN)✓$(NC) GitHub CLI already installed"; \
	else \
		echo "$(YELLOW)[INSTALL]$(NC) Installing GitHub CLI..."; \
		if command -v brew >/dev/null 2>&1; then \
			brew install gh; \
		elif command -v apt-get >/dev/null 2>&1; then \
			type -p curl >/dev/null || sudo apt install curl -y; \
			curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg; \
			chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg; \
			echo "deb [arch=$$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null; \
			sudo apt update; \
			sudo apt install gh -y; \
		else \
			echo "$(YELLOW)[ERROR]$(NC) Please install GitHub CLI manually: https://cli.github.com/"; \
			exit 1; \
		fi; \
	fi
	@echo "$(BLUE)[AUTH]$(NC) Checking GitHub authentication..."
	@if gh auth status >/dev/null 2>&1; then \
		echo "$(GREEN)✓$(NC) Already authenticated"; \
		gh auth status; \
	else \
		echo "$(YELLOW)[SETUP]$(NC) Please authenticate with GitHub..."; \
		gh auth login; \
	fi
	@echo "$(GREEN)✓$(NC) GitHub CLI ready! You can now use:"
	@echo "  make gh-status      # Check artifact status"
	@echo "  make gh-fix-missing # Fix missing artifacts"
	@echo "  make gh-release     # Create new release"

# BUILD: Watch for changes and rebuild (development)
watch: ## Watch for changes and rebuild automatically
	@echo "$(BLUE)[BUILD]$(NC) Watching for changes..."
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	@while true; do \
		inotifywait -r -e modify,create,delete lib/ native/ --exclude '_build|target' 2>/dev/null || true; \
		echo "$(GREEN)[REBUILD]$(NC) Files changed, rebuilding..."; \
		make dev; \
		echo "$(GREEN)[READY]$(NC) Build complete, watching for changes..."; \
	done

# BUILD: Quick test for continuous development
quick: ## Quick build and test for development
	@echo "$(BLUE)[BUILD]$(NC) Quick build and test..."
	MIX_ENV=test mix compile --warnings-as-errors
	mix test --max-failures=1

# BUILD: Memory and performance profiling
profile: bench ## Profile memory and performance
	@echo "$(BLUE)[BUILD]$(NC) Starting profiling session..."
	@echo "Use tools like:"
	@echo "  - mix profile.eprof"
	@echo "  - mix profile.cprof" 
	@echo "  - mix profile.fprof"
	@echo "  - cargo flamegraph (in native/jsonld_nif/)"

# BUILD: Security audit
audit: ## Run security audit
	@echo "$(BLUE)[BUILD]$(NC) Running security audit..."
	mix deps.audit
	cd native/jsonld_nif && cargo audit

# BUILD: Check for outdated dependencies
outdated: ## Check for outdated dependencies
	@echo "$(BLUE)[BUILD]$(NC) Checking for outdated dependencies..."
	mix hex.outdated
	cd native/jsonld_nif && cargo outdated

# BUILD: Local preflight cross-build of Linux precompiled NIFs
preflight: ## Build and package Linux gnu+musl artifacts locally (outputs to work/precompiled)
	@echo "$(BLUE)[BUILD]$(NC) Running local preflight (no features)..."
	bash scripts/preflight.sh

preflight-ssi: ## Build and package Linux artifacts with ssi_urdna2015 feature
	@echo "$(BLUE)[BUILD]$(NC) Running local preflight with FEATURES=ssi_urdna2015..."
	FEATURES=ssi_urdna2015 bash scripts/preflight.sh

preflight-aarch64: ## Preflight for aarch64-only (skip x86_64)
	@echo "$(BLUE)[BUILD]$(NC) Running local preflight for aarch64-only..."
	SKIP_X86_64=1 bash scripts/preflight.sh

preflight-ssi-aarch64: ## Preflight with ssi feature for aarch64-only (skip x86_64)
	@echo "$(BLUE)[BUILD]$(NC) Running local preflight ssi for aarch64-only..."
	SKIP_X86_64=1 FEATURES=ssi_urdna2015 bash scripts/preflight.sh

preflight-gnu-only: ## Preflight GNU targets only (skip MUSL)
	@echo "$(BLUE)[BUILD]$(NC) Running preflight for GNU-only targets..."
	SKIP_MUSL=1 bash scripts/preflight.sh

preflight-gnu-ssi: ## Preflight GNU targets only with ssi feature
	@echo "$(BLUE)[BUILD]$(NC) Running preflight for GNU-only targets with ssi..."
	SKIP_MUSL=1 FEATURES=ssi_urdna2015 bash scripts/preflight.sh

preflight-musl-only: ## Preflight MUSL targets only (skip GNU)
	@echo "$(BLUE)[BUILD]$(NC) Running preflight for MUSL-only targets..."
	SKIP_GNU=1 bash scripts/preflight.sh

preflight-musl-ssi: ## Preflight MUSL targets only with ssi feature
	@echo "$(BLUE)[BUILD]$(NC) Running preflight for MUSL-only targets with ssi..."
	SKIP_GNU=1 FEATURES=ssi_urdna2015 bash scripts/preflight.sh

preflight-check: ## Verify cross Docker images exist for selected subset (no build)
	@echo "$(BLUE)[BUILD]$(NC) Verifying cross images for GNU+MUSL targets..."
	bash scripts/preflight_check.sh
