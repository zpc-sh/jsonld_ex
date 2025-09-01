# Changelog

All notable changes to this project will be documented in this file.

## [0.4.1] - 2025-09-01

### Added
- Two-way spec workflow Mix tasks under `lib/mix/tasks/spec.*` (lint, render, bundle/unbundle, export, hub init/sync/index, apply, autosync, status, etc.).
- `mix spec.apply` hardened: RFC6902 (copy/move, array `/-` append), RFC7396 merge, baseline hash and Git rev checks, pointer existence checks, type-change guard (overrideable), unified diff previews, JSON summaries, and output formatting control (compact/pretty).
- `mix spec.check` meta-task and `mix spec.hash` to emit stable_json and (when available) URDNA2015 hashes.
- Canonicalization/hash API: `JSONLD.c14n/2`, `JSONLD.hash/2` (default form `:stable_json`), and `JSONLD.equal?/3` with telemetry and ETS-backed c14n cache.
- Optional ssi integration (feature `ssi_urdna2015`, pinned `ssi=0.11.0`), with safe interim deterministic N-Quads ordering; provider selection via ENV/config with sensible defaults.
- Precompiled NIFs via `rustler_precompiled`; added release workflow to build default and ssi-enabled artifacts for macOS/Linux (x86_64/aarch64) with per-file `.sha256` and aggregate `checksums.txt`.
- CI workflow validating both base build and ssi-enabled build on every push/PR.

### Changed
- Default hashing form to `:stable_json` for performance/determinism; URDNA2015 available when provider is enabled.
- Loader prefers ssi-enabled precompiled artifacts by default (override with `JSONLD_NIF_FEATURES=none`).

### Fixed
- `.gitignore` tightened to avoid committing native build outputs and workflow artifacts; removed tracked native blobs.

### Docs
- README updated with API quick start, provider selection, precompiled NIFs, CI badges, and spec.apply flags.

## [0.1.0] - 2025-01-30

### Added
- Initial release
- Core JSON-LD processing functionality
- Rust NIF implementation
