New Spec Workflow – Thoughts, Concerns, and Recommendations

Summary
- Purpose: Facilitate two-way spec change discussions via local folders, messages, bundles, and hub sync.
- Key pieces: `work/spec_requests/<id>/` layout, Mix tasks (`spec.lint`, `spec.thread.render`, `spec.bundle`/`unbundle`, `spec.apply`, `spec.export.jsonld`, `spec.hub.init`/`sync`, `spec.index`), JSON-LD export, hub index.
- Current state: Functional baseline with good ergonomics; a few decision points and guardrails to clarify.

Strengths
- Clear locality: All working artifacts live under `work/spec_requests/<id>` and stay out of Git by default.
- Deterministic artifacts: `thread.md`, JSON-LD exports, and bundles help reproduce and review discussions.
- Hub integration: `spec.hub.sync` and `spec.index` make it easy to publish and browse across projects.
- Patch automation: `spec.apply` provides a concrete, testable route from proposals to code changes.
- Modularity: Tasks are small and composable; failures are surfaced early by `spec.lint`.

Risks & Concerns
- Message authenticity: No signing/verification; `created_at` is trusted input and may be spoofed.
- Ordering semantics: Sort by `created_at` (or `id`) can misorder messages across timezones/clock skew.
- Attachments safety: Arbitrary paths are allowed; risk of secrets/large files or path traversal if not normalized.
- Patch scope & safety: JSON Pointer ops are limited (add/replace/remove) and applied without baseline/version checks.
- Schema drift: Request/message/ack schemas may evolve; versioning and compatibility are not encoded.
- JSON-LD context: Uses a relative `@context` path; portability across hubs and offline scenarios may break.
- Index recency: `spec.index` uses file mtimes; this can be reset on copy/clone and may not reflect logical updates.
- Large artifacts: Bundles are zip files under `work/`; repeated attachments can bloat local storage without LFS.
- Hub consistency: `spec.hub.init` and `spec.export.docs` must stay aligned with the latest schema/contexts.

Open Questions
- Identity & trust: How do we authenticate authors (PGP/GPG, OIDC claims, repo-signed commits, or per-message signatures)?
- Canonical timestamps: Who assigns canonical `created_at`? Should the hub enforce/normalize timestamps on ingest?
- ID strategy: Should `<id>` be timestamp-based, monotonic, or human-readable? How to avoid collisions across projects?
- Status lifecycle: What are allowed transitions (proposed → accepted/in_progress → done/rejected/blocked)? Any gates?
- Patch baselines: Should proposals include a content hash or base revision to detect drift before applying?
- Attachment hosting: Keep inside `work/` vs. external object store (signed URLs) for large artifacts? Retention policy?
- Transport: Will `spec.msg.push`/`pull` integrate with a remote API or Git-only flows (PRs/issues)?
- Archival: When requests close, where do artifacts live long-term (hub only, tarball, both)? What’s discoverability policy?

Recommendations
- Provenance & integrity
  - Require ISO 8601 UTC timestamps; optionally have the hub stamp and validate on ingest.
  - Add optional message signing (e.g., detached signature over JSON body) and verify on lint/export.
  - Embed `from.project/agent` and an `origin` field (local, hub-sync, api) for auditability.
- Robust ordering
  - Sort primarily by `created_at`, secondarily by a monotonic message `id` or hub sequence.
  - Allow `thread.render` to optionally re-order using a hub-provided canonical order map.
- Safer patches
  - Extend `spec.apply` with baseline checks: accept an optional file hash or Git rev and fail on mismatch.
  - Add a dry-run mode with diff output; log JSON Pointer paths applied; validate pointer existence for replace/remove.
  - Expand JSON Pointer coverage (array tail `-`, object creation rules) and add unit tests for edge cases.
- Schemas & versioning
  - Introduce `schemaVersion` for request/message/ack; publish `v1`, `v1.1` contexts in `schemas/contexts/`.
  - Validate messages and acks against schemas in `spec.lint` (not just parse JSON).
- Hub & context
  - Ship a stable `spec.jsonld` context in the hub and prefer absolute or hub-root-relative `@context` URLs.
  - Include `updatedAt` in exported JSON-LD; derive hub index recency from JSON-LD fields over mtime.
- Storage & size
  - Enforce per-attachment size limits in lint; recommend external hosting for large files with checksums.
  - Consider optional Git LFS for local convenience, while keeping `work/` ignored by default.
- Developer ergonomics
  - Add `mix spec.check` to run lint + thread.render + basic schema validation in one shot.
  - Provide `mix spec.msg.new` templates and guard rails for required fields.
  - Add `--no-thread` or `--only-errors` flags to speed up lint in CI.

Two-Way Expectations
- Requester (proposing side)
  - Provide clear `request.json` aligned with `schema.json`, minimal reproducible examples, and proposed patches.
  - Keep attachments small and relevant; include checksums for larger files.
  - Use consistent timestamps and include timezone-agnostic ISO 8601 values.
  - Reply via `outbox/` with context (`ref.path`, `ref.json_pointer`) when discussing specific files.
- Receiver (owning side)
  - Acknowledge with `ack.json` including `owner`, `contact`, `status`, and `eta` where possible.
  - Use `inbox/` to respond; prefer structured feedback and concrete `patch.json` when suggesting changes.
  - When accepting, provide a clear status transition and merge plan; when rejecting, include rationale.

Near-Term Enhancements (Low Lift)
- Add message validation in `spec.lint` against `message.schema.json` and `ack.schema.json`.
- Normalize/validate relative attachment paths; prevent traversal outside the request root.
- Ensure `work/spec_requests/contexts/spec.jsonld` exists or document where to fetch it.
- Add unit tests for `spec.apply` pointer operations and error modes.
- Emit a machine-readable summary (JSON) from `spec.lint` for CI consumption.

Decision Points To Align On
- Message signing requirement and mechanism.
- Canonical ID and timestamp policy (assignment, format, uniqueness).
- Patch application rules (baseline verification, dry-run default, failure semantics).
- Hub context URL strategy (relative vs. absolute) and versioning.
- Size limits and hosting for attachments; retention/archival policy in the hub.

Appendix – File/Task Map
- `work/spec_requests/<id>/request.json`: Top-level proposal (see `schema.json`).
- `work/spec_requests/<id>/{inbox,outbox}/msg_*.json`: Message exchanges (see `message.schema.json`).
- `work/spec_requests/<id>/thread.md`: Rendered discussion log.
- `mix spec.thread.render`: Renders thread.
- `mix spec.lint`: Validates JSON, attachments, renders thread.
- `mix spec.apply`: Applies `patch.json` attachments to target repo.
- `mix spec.bundle` / `mix spec.unbundle`: Share and import bundles.
- `mix spec.export.jsonld`: Export request/ack/messages as JSON-LD to hub.
- `mix spec.hub.init` / `mix spec.hub.sync` / `mix spec.index`: Initialize, sync, and index hub content.

