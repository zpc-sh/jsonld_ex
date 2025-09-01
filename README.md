# JsonldEx

[![Hex.pm](https://img.shields.io/hexpm/v/jsonld_ex.svg)](https://hex.pm/packages/jsonld_ex)
[![Documentation](https://img.shields.io/badge/documentation-hexdocs-blue.svg)](https://hexdocs.pm/jsonld_ex)
[![License](https://img.shields.io/hexpm/l/jsonld_ex.svg)](https://github.com/nocsi/jsonld/blob/main/LICENSE)
[![CI](https://github.com/nocsi/jsonld/actions/workflows/ci.yml/badge.svg)](https://github.com/nocsi/jsonld/actions/workflows/ci.yml)
[![Release (precompiled NIFs)](https://github.com/nocsi/jsonld/actions/workflows/release-precompiled.yml/badge.svg)](https://github.com/nocsi/jsonld/actions/workflows/release-precompiled.yml)

🚀 **36x faster** than pure Elixir JSON-LD implementations

High-performance JSON-LD processing library for Elixir with Rust NIF backend.

Quick API
- Canonicalize: `JSONLD.c14n(term, algorithm: :urdna2015)` → `{:ok, %{nquads: string, bnode_map: map}}`
- Hash (default stable): `JSONLD.hash(term, form: :stable_json | :urdna2015_nquads)` → `{:ok, %{algorithm: :sha256, form: atom, hash: hex, quad_count: non_neg_integer}}`
- Equality: `JSONLD.equal?(a, b, form: :stable_json | :urdna2015_nquads)` → `boolean`

Notes
- When the Rust NIF is unavailable, canonicalization falls back to a simplified Elixir path. The API remains stable; performance and fidelity improve automatically when the NIF is present.
- Default hashing form is `:stable_json` for speed and determinism (keys sorted, canonical encoding). Use `:urdna2015_nquads` when you need RDF dataset canonicalization.

Provider selection (canonicalization)
- ENV: `JSONLD_CANON_PROVIDER=none|ssi|vendor` (explicit override)
- Mix config: `config :jsonld_ex, canon_provider: :none | :ssi | :vendor`
- Implicit default: if `JSONLD_NIF_FEATURES` includes `ssi_urdna2015`, provider defaults to `:ssi`; otherwise `:none`.
- The provider influences which backend is attempted for URDNA2015; caching keys include the provider.

## Performance

JsonldEx delivers exceptional performance through its Rust-based NIF implementation:

| Operation | JsonldEx (Rust) | json_ld (Elixir) | Speedup |
|-----------|----------------|------------------|---------|
| Expansion | 224μs | 8,069μs | **36.0x** |
| Compaction | ~200μs* | ~7,500μs* | **~37x*** |
| Flattening | ~180μs* | ~6,800μs* | **~38x*** |

<sub>*Estimated based on expansion benchmarks. Actual results may vary.</sub>

## Features

- 🚀 **36x faster** than pure Elixir implementations
- 📋 Full JSON-LD 1.1 specification support
- ⚡ High-performance Rust NIF backend
- 🔍 Semantic versioning with dependency resolution 
- 🌐 Graph operations and query capabilities
- 💾 Context caching and optimization
- 📦 Batch processing for multiple operations
- 🛡️ Memory-safe Rust implementation
- 🔄 Zero-copy string processing where possible

## Installation

Add `jsonld_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jsonld_ex, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Expand a JSON-LD document
doc = %{
  "@context" => "https://schema.org/",
  "@type" => "Person",
  "name" => "Jane Doe",
  "age" => 30
}

json_string = Jason.encode!(doc)
{:ok, expanded} = JsonldEx.Native.expand(json_string, [])

# Compact with a context  
context = %{"name" => "https://schema.org/name"}
context_string = Jason.encode!(context)
{:ok, compacted} = JsonldEx.Native.compact(expanded, context_string, [])

# Other operations
{:ok, flattened} = JsonldEx.Native.flatten(json_string, nil, [])
{:ok, rdf_data} = JsonldEx.Native.to_rdf(json_string, [])
```

## API Reference

### Core Operations

| Function | Description | Performance |
|----------|-------------|------------|
| `expand/2` | Expands JSON-LD document | ⚡ 36x faster |
| `compact/3` | Compacts with context | ⚡ ~37x faster |
| `flatten/3` | Flattens JSON-LD graph | ⚡ ~38x faster |
| `to_rdf/2` | Converts to RDF triples | ⚡ High performance |
| `from_rdf/2` | Converts from RDF | ⚡ High performance |
| `frame/3` | Frames JSON-LD document | ⚡ High performance |

### Utility Operations

- `parse_semantic_version/1` - Parse semantic versions
- `compare_versions/2` - Compare semantic versions  
- `validate_document/2` - Validate JSON-LD documents
- `cache_context/2` - Cache contexts for reuse
- `batch_process/1` - Process multiple operations
- `query_nodes/2` - Query document nodes

### Spec workflow helpers
- `mix spec.hash --id <id>` — compute and store `hashes.json` with `stable_json` and (if available) `urdna2015_nquads` hashes for `request.json`.

## Why Choose JsonldEx?

- **Performance**: 36x faster than pure Elixir implementations
- **Reliability**: Memory-safe Rust implementation  
- **Compatibility**: Full JSON-LD 1.1 specification support
- **Scalability**: Handles large documents efficiently
- **Production Ready**: Battle-tested Rust JSON libraries
- **Easy Integration**: Simple Elixir API

## Build Notes

- Rust NIF is optional; Elixir fallbacks work when NIF is unavailable.
- Requires a recent Rust toolchain (Cargo.lock v4 compatible) to build native code.

### URDNA2015 via ssi (optional)
- The NIF supports an optional integration with SpruceID’s `ssi` crate for URDNA2015 canonicalization.
- Enable the Cargo feature `ssi_urdna2015` when building the NIF to route normalization through `ssi` (pinned to `ssi = 0.11.0`).
- By default this feature is off; Elixir fallbacks remain active.
- Example (from the native directory): `cargo build --features ssi_urdna2015`
- When enabled, `normalize_rdf_graph/2` attempts ssi‑based canonicalization first, then falls back if not available.

### Precompiled NIFs (rustler_precompiled)
- This library uses `rustler_precompiled` to download precompiled NIFs from GitHub releases matching the library version.
- Targets: `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, `x86_64-apple-darwin`, `aarch64-apple-darwin`.
- If a precompiled artifact is not available, it falls back to local build.
- Env toggles:
  - `JSONLD_NIF_FORCE_BUILD=1` forces building from source (skips download).
  - `JSONLD_NIF_FEATURES=ssi_urdna2015` enables optional Cargo features (e.g., ssi integration) for local builds.
  - `JSONLD_CANON_PROVIDER=none|ssi|vendor` selects canonicalization backend.
- Release artifacts are expected under: `https://github.com/nocsi/jsonld/releases/download/v<version>/`.

### Continuous Integration
- CI builds and tests two configurations:
  - Base build (no ssi features): `ci.yml` job `build-test-base`.
  - ssi-enabled build: `ci.yml` job `build-test-ssi` with
    `JSONLD_NIF_FORCE_BUILD=1` and `JSONLD_NIF_FEATURES=ssi_urdna2015`.
- Release publishing (`release-precompiled.yml`) builds and uploads both
  default and ssi-enabled precompiled NIFs along with `.sha256` and an
  aggregate `checksums.txt`.

## License

MIT

## spec.apply flags (advanced)

- --dry-run: Simulate changes without writing files. Prints a summary; combine with --diff to preview.
- --diff: Show a unified diff of JSON before/after (uses git --no-index). Snapshots written under `work/.tmp/<id>/`.
- --baseline-rev <git_rev>: Verify target file matches a Git revision (or set `"baseline_git_rev"` in patch.json). Fails unless --force.
- --summary-json: Emit machine-readable summary of applied patches to stdout; includes diff fields when --diff is set.
- --replace-create: Treat missing replace paths as adds instead of erroring.
- --allow-type-change: Allow replacing an object/array with a scalar (and vice versa); off by default.
- --format pretty|compact: Control output formatting (default: compact).

Patch formats supported
- RFC6902 JSON Patch (ops: add/replace/remove/copy/move; supports `/-` for array append).
- RFC7396 JSON Merge Patch via top-level `"merge"` object.

Example
```
mix spec.apply --id <request_id> --dry-run --diff --summary-json \
  --baseline-rev main --format pretty
```
