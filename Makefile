# Simple Makefile for JsonldEx - NO MORE RUSTLER_PRECOMPILED!

.PHONY: help clean dev prod test docs nif-build nif-clean

.DEFAULT_GOAL := help

help: ## Show help
	@echo "JsonldEx Simple Build System (No Precompiled Nonsense!)"
	@echo ""
	@echo "Available targets:"
	@echo "  dev          Development build"
	@echo "  prod         Production build" 
	@echo "  test         Run tests"
	@echo "  docs         Generate docs"
	@echo "  clean        Clean artifacts"
	@echo "  nif-build    Build NIF (same as dev)"
	@echo "  nif-clean    Clean NIF (same as clean)"

clean: ## Clean all build artifacts
	@echo "[BUILD] Cleaning..."
	mix clean --deps
	rm -rf _build deps/_build native/target

dev: ## Development build
	@echo "[BUILD] Development build..."
	mix deps.get
	mix compile

prod: ## Production build
	@echo "[BUILD] Production build..."
	MIX_ENV=prod mix deps.get
	MIX_ENV=prod mix compile

test: ## Run tests
	@echo "[TEST] Running tests..."
	mix test

docs: ## Generate documentation
	@echo "[DOCS] Generating documentation..."
	mix docs

# Legacy aliases for old habits
nif-build: dev ## Build NIF (just builds from source like it should)
	@echo "✓ NIF built successfully (no more precompiled hell!)"

nif-clean: clean ## Clean NIF artifacts
	@echo "✓ NIF artifacts cleaned"
