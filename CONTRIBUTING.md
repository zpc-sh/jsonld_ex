Contributing to JsonldEx

Thanks for considering a contribution! This project welcomes pull requests and issues. This guide explains how to get set up and how we work.

Getting started
- Requirements: Elixir ≥ 1.15, Erlang/OTP ≥ 26, Rust (stable), Cargo.
- Optional: Docker/Colima for cross builds; Zig for MUSL builds.
- Install deps: `mix deps.get`
- Build and test: `mix compile && mix test`
- Native NIF (optional): `cd native/jsonld_nif && cargo build`

Local development
- Format: `mix format` and `cargo fmt` (CI enforces formatting).
- Lint: `mix credo --strict` and `cargo clippy -- -D warnings`.
- Quick iteration: `make dev` or run Elixir and Rust builds separately.

Precompiled NIFs
- We use `rustler_precompiled` and publish artifacts on GitHub Releases.
- Local fallback builds are automatic if an artifact is missing.
- Release workflow runs on published releases and can be manually dispatched.

Commit/PR guidelines
- Keep changes focused; include tests when practical.
- Make sure `mix test` passes and linters are clean.
- Describe the change and rationale in the PR description.
- Link related issues or discussions.

Branching & releases
- Main is protected by CI.
- Tags `v<version>` trigger the docs/release flows (see README for details).

Reporting bugs
- Use the Bug Report template. Include steps to reproduce, expected/actual behavior, and environment.

Security
- Please do not open public issues for security problems. See SECURITY.md for reporting instructions.

Code of Conduct
- Participation is governed by the Contributor Covenant (see CODE_OF_CONDUCT.md).

