#!/bin/bash
# BUILD: Advanced build script with optimization profiles

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# BUILD: Print colored output
print_step() {
    echo -e "${BLUE}[BUILD]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# BUILD: Check if we're on Apple Silicon for SIMD optimizations
check_simd_support() {
    # Respect cross-compilation: only add CPU-specific flags when building for host target
    local host_triple target_triple host_arch target_arch
    host_triple=$(rustc -vV | awk -F ': ' '/^host:/{print $2}')
    target_triple=${CARGO_BUILD_TARGET:-$host_triple}
    host_arch=${host_triple%%-*}
    target_arch=${target_triple%%-*}

    if [[ "$host_triple" != "$target_triple" ]]; then
        print_warning "Cross-compiling for $target_triple; skipping CPU-specific SIMD flags"
        return
    fi

    if [[ $(uname -s) == "Darwin" && $(uname -m) == "arm64" ]]; then
        print_success "Apple Silicon (arm64) detected - enabling NEON"
        export RUSTFLAGS="$RUSTFLAGS -C target-feature=+neon"
    elif [[ -r /proc/cpuinfo ]] && grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
        print_success "x86_64 AVX2 detected - enabling AVX2"
        export RUSTFLAGS="$RUSTFLAGS -C target-feature=+avx2"
    else
        print_warning "No advanced SIMD support detected or unavailable to probe"
    fi
}

# BUILD: Environment setup
setup_environment() {
    print_step "Setting up build environment..."
    
    # Check for required tools
    if ! command -v cargo &> /dev/null; then
        print_error "Rust/Cargo not found. Please install Rust first."
        exit 1
    fi
    
    if ! command -v mix &> /dev/null; then
        print_error "Mix not found. Please install Elixir first."
        exit 1
    fi
    
    # Set baseline RUSTFLAGS only for native builds; avoid target-cpu=native when cross-compiling
    local host_triple target_triple
    host_triple=$(rustc -vV | awk -F ': ' '/^host:/{print $2}')
    target_triple=${CARGO_BUILD_TARGET:-$host_triple}
    if [[ "$host_triple" == "$target_triple" ]]; then
        export RUSTFLAGS="${RUSTFLAGS:--C target-cpu=native}"
    else
        export RUSTFLAGS="${RUSTFLAGS:-}"
    fi
    
    check_simd_support
}

# BUILD: Clean all build artifacts
clean_all() {
    print_step "Cleaning all build artifacts..."
    
    # Clean Elixir build
    mix clean
    rm -rf _build/
    
    # Clean Rust build
    cd native/jsonld_nif
    cargo clean
    cd ../..
    
    # Clean benchmark results
    rm -rf bench/results/
    
    print_success "All build artifacts cleaned"
}

# BUILD: Fast development build
build_dev() {
    print_step "Building for development (fast compilation)..."
    
    export MIX_ENV=dev
    export CARGO_PROFILE=dev
    
    # Use incremental compilation for faster builds
    export RUSTFLAGS="$RUSTFLAGS -C incremental=true"
    
    mix deps.get
    mix compile
    
    print_success "Development build completed"
}

# BUILD: Production build with full optimizations
build_prod() {
    print_step "Building for production (full optimizations)..."
    
    export MIX_ENV=prod
    export CARGO_PROFILE=production
    
    # Maximum optimization flags
    export RUSTFLAGS="$RUSTFLAGS -C lto=fat -C codegen-units=1 -C panic=abort"
    
    mix deps.get
    mix compile
    
    print_success "Production build completed"
}

# BUILD: Benchmark build with profiling symbols
build_bench() {
    print_step "Building for benchmarking..."
    
    export MIX_ENV=bench
    export CARGO_PROFILE=bench
    
    # Keep debug symbols for profiling
    export RUSTFLAGS="$RUSTFLAGS -C debug-assertions=off"
    
    mix deps.get
    mix compile
    
    print_success "Benchmark build completed"
}

# BUILD: Test build with coverage
build_test() {
    print_step "Building for testing with coverage..."
    
    export MIX_ENV=test
    export CARGO_PROFILE=fast-build
    
    mix deps.get
    mix compile
    mix test
    
    print_success "Test build completed"
}

# BUILD: Run comprehensive benchmarks
run_benchmarks() {
    print_step "Running comprehensive benchmarks..."
    
    build_bench
    
    # Create results directory
    mkdir -p bench/results
    
    # Run our turbo benchmark
    print_step "Running turbo benchmark..."
    mix run bench/turbo_benchmark.exs | tee bench/results/turbo_results.txt
    
    # If criterion benchmarks exist, run them
    if [ -f "native/jsonld_nif/benches/*.rs" ]; then
        print_step "Running Rust criterion benchmarks..."
        cd native/jsonld_nif
        cargo bench | tee ../../bench/results/criterion_results.txt
        cd ../..
    fi
    
    print_success "Benchmarks completed - results in bench/results/"
}

# BUILD: CI build pipeline
build_ci() {
    print_step "Running CI build pipeline..."
    
    # Clean build
    clean_all
    
    # Test different environments
    print_step "Testing dev build..."
    build_dev
    
    print_step "Testing prod build..."  
    build_prod
    
    print_step "Running tests..."
    build_test
    
    print_step "Running benchmarks..."
    run_benchmarks
    
    print_success "CI build pipeline completed successfully"
}

# BUILD: Profile-guided optimization build
build_pgo() {
    print_step "Building with Profile-Guided Optimization..."
    
    # First, build instrumented version
    export RUSTFLAGS="$RUSTFLAGS -C profile-generate=/tmp/pgo-data"
    build_prod
    
    # Run representative workload to generate profile data
    print_step "Generating profile data..."
    mix run bench/turbo_benchmark.exs > /dev/null
    
    # Rebuild with profile data
    export RUSTFLAGS="$RUSTFLAGS -C profile-use=/tmp/pgo-data"
    export RUSTFLAGS="${RUSTFLAGS/-C profile-generate=\/tmp\/pgo-data/}"
    
    clean_all
    build_prod
    
    print_success "PGO build completed"
}

# BUILD: Main command dispatcher
case "${1:-help}" in
    "clean")
        setup_environment
        clean_all
        ;;
    "dev")
        setup_environment
        build_dev
        ;;
    "prod")
        setup_environment
        build_prod
        ;;
    "test")
        setup_environment
        build_test
        ;;
    "bench")
        setup_environment
        run_benchmarks
        ;;
    "ci")
        setup_environment
        build_ci
        ;;
    "pgo")
        setup_environment
        build_pgo
        ;;
    "help"|*)
        echo "JsonldEx Advanced Build System"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  clean   - Clean all build artifacts"
        echo "  dev     - Fast development build"
        echo "  prod    - Production build with full optimizations"
        echo "  test    - Test build with coverage"
        echo "  bench   - Run comprehensive benchmarks"
        echo "  ci      - Full CI build pipeline"
        echo "  pgo     - Profile-Guided Optimization build"
        echo "  help    - Show this help"
        echo ""
        echo "Environment variables:"
        echo "  RUSTFLAGS - Additional Rust compiler flags"
        echo "  MIX_ENV   - Elixir environment (overrides command default)"
        echo ""
        ;;
esac
