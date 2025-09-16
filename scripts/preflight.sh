#!/usr/bin/env bash
set -euo pipefail

# Local preflight builder for precompiled NIF artifacts.
# - Builds Linux GNU and MUSL variants for x86_64 and aarch64
# - Packages tarballs with names expected by rustler_precompiled
# - Optionally builds feature variants (e.g., FEATURES=ssi_urdna2015)
#
# Requirements (recommended):
# - Docker
# - cross (cargo install cross)
#
# Optional (when cross is not available for MUSL):
# - cargo-zigbuild (cargo install cargo-zigbuild) and Zig

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
NATIVE_DIR="$ROOT_DIR/native/jsonld_nif"
OUT_DIR="$ROOT_DIR/work/precompiled"
mkdir -p "$OUT_DIR"

FEATURES=${FEATURES:-}
# Optional skip flags for local runs
SKIP_X86_64=${SKIP_X86_64:-}
SKIP_AARCH64=${SKIP_AARCH64:-}
SKIP_GNU=${SKIP_GNU:-0}
SKIP_MUSL=${SKIP_MUSL:-0}
NIF_VERSIONS=(2.16 2.15 2.14)
LINUX_GNU_TARGETS=(x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu)
LINUX_MUSL_TARGETS=(x86_64-unknown-linux-musl aarch64-unknown-linux-musl)

version_from_mix() {
  awk -F '"' '/version:/ {print $2; exit}' "$ROOT_DIR/mix.exs"
}

VERSION=${VERSION:-$(version_from_mix)}
if [[ -z "$VERSION" ]]; then
  echo "Unable to determine version from mix.exs; set VERSION env" >&2
  exit 1
fi

have() { command -v "$1" >/dev/null 2>&1; }

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
docker_ready() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }

# If running on Apple Silicon/aarch64 hosts and skip flags unset, default to skipping x86_64
host_arch=$(uname -m || echo unknown)
if [[ -z "${SKIP_X86_64}" && "$host_arch" =~ ^(aarch64|arm64)$ ]]; then
  SKIP_X86_64=1
fi
if [[ -z "${SKIP_AARCH64}" ]]; then
  SKIP_AARCH64=0
fi
if [[ -z "${SKIP_X86_64}" ]]; then
  SKIP_X86_64=0
fi

build_with_cross() {
  local target=$1
  local features_flag=()
  [[ -n "$FEATURES" ]] && features_flag=(--features "$FEATURES")
  if ! have cross; then
    echo "[preflight] 'cross' not found. Install with: cargo install cross" >&2
    exit 3
  fi
  (
    cd "$NATIVE_DIR" \
    && env -u RUSTUP_TOOLCHAIN \
       DOCKER_DEFAULT_PLATFORM=${DOCKER_DEFAULT_PLATFORM:-linux/amd64} \
       CROSS_CONTAINER_ENGINE=${CROSS_CONTAINER_ENGINE:-docker} \
       CROSS_FORCE_DOCKER=1 \
       cross build --release --target "$target" "${features_flag[@]}"
  )
}

build_with_cargo() {
  local target=$1
  local features_flag=()
  [[ -n "$FEATURES" ]] && features_flag=(--features "$FEATURES")
  rustup target add "$target" >/dev/null 2>&1 || true
  (cd "$NATIVE_DIR" && cargo build --release --target "$target" "${features_flag[@]}")
}

build_with_zig() {
  local target=$1
  local features_flag=()
  [[ -n "$FEATURES" ]] && features_flag=(--features "$FEATURES")
  rustup target add "$target" >/dev/null 2>&1 || true
  (cd "$NATIVE_DIR" && cargo zigbuild --release --target "$target" "${features_flag[@]}")
}

package_artifact() {
  local target=$1
  local nif_version=$2
  local libname ext src out
  case "$target" in
    *apple-darwin) ext=dylib ; libname=libjsonld_nif.$ext ;;
    *)             ext=so    ; libname=libjsonld_nif.$ext ;;
  esac
  src="$NATIVE_DIR/target/$target/release/$libname"
  if [[ ! -f "$src" ]]; then
    echo "Missing compiled library for $target ($src)" >&2
    return 1
  fi
  local suffix=""
  [[ -n "$FEATURES" ]] && suffix="-features-$FEATURES"
  out="$OUT_DIR/libjsonld_nif-v${VERSION}-nif-${nif_version}-${target}${suffix}.tar.gz"
  tar -C "$(dirname "$src")" -czf "$out" "$(basename "$src")"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$out" | awk '{print $1 "  " $2}' > "$out.sha256"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$out" | awk '{print $1 "  " $2}' > "$out.sha256"
  else
    echo "Warning: no sha256 tool found; skipping checksum for $out" >&2
  fi
  echo "Built: $out"
}

build_target() {
  local target=$1
  if docker_ready; then
    build_with_cross "$target"
  else
    if [[ "$target" == *musl* ]]; then
      if have cargo-zigbuild; then
        build_with_zig "$target"
      else
        echo "[preflight] Docker not available; for MUSL targets install 'cargo-zigbuild' and Zig (or start Docker)." >&2
        exit 2
      fi
    else
      echo "[preflight] Docker required for GNU target $target on this host. Please start Docker/Colima." >&2
      exit 2
    fi
  fi
}

echo "==> Preflight build: VERSION=$VERSION FEATURES=${FEATURES:-<none>}"

BUILD_GNU=1
if [[ "$SKIP_GNU" -eq 1 ]]; then
  BUILD_GNU=0
fi
if is_darwin && ! docker_ready; then
  echo "[preflight] Docker not available; GNU targets require cross+Docker on macOS. Skipping GNU targets." >&2
  BUILD_GNU=0
fi

for nif in "${NIF_VERSIONS[@]}"; do
  if [[ "$BUILD_GNU" -eq 1 ]]; then
    for t in "${LINUX_GNU_TARGETS[@]}"; do
      if [[ "$SKIP_X86_64" -eq 1 && "$t" == x86_64-* ]]; then
        echo "[preflight] Skipping $t due to SKIP_X86_64=1"
        continue
      fi
      if [[ "$SKIP_AARCH64" -eq 1 && "$t" == aarch64-* ]]; then
        echo "[preflight] Skipping $t due to SKIP_AARCH64=1"
        continue
      fi
      echo "-- Building target=$t nif=$nif"
      build_target "$t"
      package_artifact "$t" "$nif"
    done
  fi
  if [[ "$SKIP_MUSL" -ne 1 ]]; then
    for t in "${LINUX_MUSL_TARGETS[@]}"; do
      if [[ "$SKIP_X86_64" -eq 1 && "$t" == x86_64-* ]]; then
        echo "[preflight] Skipping $t due to SKIP_X86_64=1"
        continue
      fi
      if [[ "$SKIP_AARCH64" -eq 1 && "$t" == aarch64-* ]]; then
        echo "[preflight] Skipping $t due to SKIP_AARCH64=1"
        continue
      fi
      echo "-- Building target=$t nif=$nif"
      build_target "$t"
      package_artifact "$t" "$nif"
    done
  else
    echo "[preflight] Skipping MUSL targets due to SKIP_MUSL=1"
  fi
done

echo "==> Done. Artifacts in $OUT_DIR"
