#!/usr/bin/env bash
set -euo pipefail

# Preflight environment check: verify cross Docker images can be pulled
# for the selected target subset. Does not build or package.

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

FEATURES=${FEATURES:-}
SKIP_X86_64=${SKIP_X86_64:-}
SKIP_AARCH64=${SKIP_AARCH64:-}
SKIP_GNU=${SKIP_GNU:-0}
SKIP_MUSL=${SKIP_MUSL:-0}

NIF_VERSIONS=(2.16 2.15 2.14)
LINUX_GNU_TARGETS=(x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu)
LINUX_MUSL_TARGETS=(x86_64-unknown-linux-musl aarch64-unknown-linux-musl)

have() { command -v "$1" >/dev/null 2>&1; }
docker_ready() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }

# Default skip x86_64 on arm64 hosts unless explicitly overridden
host_arch=$(uname -m || echo unknown)
if [[ -z "${SKIP_X86_64}" && "$host_arch" =~ ^(aarch64|arm64)$ ]]; then
  SKIP_X86_64=1
fi
if [[ -z "${SKIP_AARCH64}" ]]; then SKIP_AARCH64=0; fi
if [[ -z "${SKIP_X86_64}" ]]; then SKIP_X86_64=0; fi

require_cross_image() {
  local target=$1
  local platform="--platform=${CROSS_IMAGE_PLATFORM:-linux/amd64}"
  local image_base="ghcr.io/cross-rs/${target}"
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
    echo "[preflight-check] FAIL: cannot pull ${image_base}:{${tags[*]}} for $platform" >&2
    return 1
  fi
  echo "[preflight-check] OK: ${image} ${platform}"
}

if ! docker_ready; then
  echo "[preflight-check] Docker not available. Start Docker/Colima." >&2
  exit 2
fi

ret=0

if [[ "$SKIP_GNU" -ne 1 ]]; then
  for t in "${LINUX_GNU_TARGETS[@]}"; do
    if [[ "$SKIP_X86_64" -eq 1 && "$t" == x86_64-* ]]; then
      echo "[preflight-check] Skip $t (SKIP_X86_64=1)"
      continue
    fi
    if [[ "$SKIP_AARCH64" -eq 1 && "$t" == aarch64-* ]]; then
      echo "[preflight-check] Skip $t (SKIP_AARCH64=1)"
      continue
    fi
    require_cross_image "$t" || ret=1
  done
else
  echo "[preflight-check] Skipping GNU (SKIP_GNU=1)"
fi

if [[ "$SKIP_MUSL" -ne 1 ]]; then
  for t in "${LINUX_MUSL_TARGETS[@]}"; do
    if [[ "$SKIP_X86_64" -eq 1 && "$t" == x86_64-* ]]; then
      echo "[preflight-check] Skip $t (SKIP_X86_64=1)"
      continue
    fi
    if [[ "$SKIP_AARCH64" -eq 1 && "$t" == aarch64-* ]]; then
      echo "[preflight-check] Skip $t (SKIP_AARCH64=1)"
      continue
    fi
    require_cross_image "$t" || ret=1
  done
else
  echo "[preflight-check] Skipping MUSL (SKIP_MUSL=1)"
fi

exit "$ret"

