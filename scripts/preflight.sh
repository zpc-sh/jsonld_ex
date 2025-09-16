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

# Ensure required cross image for a target can be pulled for the configured platform.
# This prevents cross from falling back to host toolchains.
require_cross_image() {
  local target=$1
  # Choose docker platform per target unless explicitly overridden by CROSS_IMAGE_PLATFORM
  local default_platform=""
  case "$target" in
    aarch64-*) default_platform="linux/arm64" ;;
    x86_64-*)  default_platform="linux/amd64" ;;
    *)         default_platform="${CROSS_IMAGE_PLATFORM:-}" ;;
  esac
  local platform=""
  if [[ -n "${CROSS_IMAGE_PLATFORM:-}" ]]; then
    platform="--platform=${CROSS_IMAGE_PLATFORM}"
  elif [[ -n "$default_platform" ]]; then
    platform="--platform=${default_platform}"
  fi
  local image_base="ghcr.io/cross-rs/${target}"
  # Per-target tag override env: CROSS_IMAGE_TAG_<target_triple>
  local target_env_key=${target//[^A-Za-z0-9]/_}
  local per_target_var="CROSS_IMAGE_TAG_${target_env_key}"
  local per_target_tag=""
  if [[ -n ${!per_target_var-} ]]; then per_target_tag="${!per_target_var}"; fi
  local tags=()
  if [[ -n "$per_target_tag" ]]; then tags+=("$per_target_tag"); fi
  if [[ -n "${CROSS_IMAGE_TAG:-}" ]]; then tags+=("${CROSS_IMAGE_TAG}"); fi
  tags+=(latest main)
  local image=""
  for tag in "${tags[@]}"; do
    if docker pull $platform "${image_base}:${tag}" >/dev/null 2>&1; then
      image="${image_base}:${tag}"
      break
    fi
  done
  if [[ -z "$image" ]]; then
    echo "[preflight] ERROR: cannot pull cross image for $target (tried tags: ${tags[*]})." >&2
    echo "          Ensure Colima/Docker can run ${CROSS_IMAGE_PLATFORM:-linux/amd64} images, or set CROSS_IMAGE_TAG(_<TARGET>)." >&2
    exit 3
  fi
  echo "[preflight] cross image ok: $image $platform"
}

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
  # Sanitize RUSTUP_TOOLCHAIN: if it's set to a non-host toolchain like
  # 'stable-x86_64-unknown-linux-gnu', strip the target triple and keep the channel only.
  # This avoids rustup trying to install an incompatible host toolchain on macOS/ARM.
  local tc="${RUSTUP_TOOLCHAIN:-stable}"
  case "$tc" in
    *-unknown-*|*-apple-*|*-linux-*|*-pc-*) tc="${tc%%-*}" ;;
  esac
  (
    # Ensure host-compatible rustup toolchain so 'cross' doesn't try to install a non-host toolchain.
    # Some environments set default toolchain to e.g. nightly-x86_64-unknown-linux-gnu, which fails on macOS/ARM.
    # Respect user-provided RUSTUP_TOOLCHAIN; otherwise default to stable.
    cd "$NATIVE_DIR" && \
      RUSTUP_TOOLCHAIN="$tc" \
      env -u DOCKER_DEFAULT_PLATFORM \
      CROSS_CONTAINER_ENGINE="${CROSS_CONTAINER_ENGINE:-docker}" \
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
    # Fail fast if the cross image can't be pulled for this target/platform
    require_cross_image "$target"
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
