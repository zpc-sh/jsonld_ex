# BUILD: Advanced Makefile for JsonldEx development

.PHONY: help clean dev prod test bench ci pgo install format lint docs release

# Default target
.DEFAULT_GOAL := help

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
	@echo "  make dev     # Fast development build"
	@echo "  make prod    # Production build with full optimizations"
	@echo "  make bench   # Run comprehensive benchmarks"
	@echo "  make ci      # Full CI pipeline"

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

# BUILD: Format code
format: ## Format Elixir and Rust code
	@echo "$(BLUE)[BUILD]$(NC) Formatting code..."
	mix format
	cd native/jsonld_nif && cargo fmt

# BUILD: Lint code
lint: ## Lint Elixir and Rust code
	@echo "$(BLUE)[BUILD]$(NC) Linting code..."
	mix credo --strict
	cd native/jsonld_nif && cargo clippy -- -D warnings

# BUILD: Generate documentation
docs: ## Generate documentation
	@echo "$(BLUE)[BUILD]$(NC) Generating documentation..."
	mix docs

# BUILD: Release build and packaging
release: prod docs ## Create a release package
	@echo "$(BLUE)[BUILD]$(NC) Creating release package..."
	mix hex.build

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