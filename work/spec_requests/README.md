Spec Request Workflow (Codex)

This folder holds local, working copies of spec change requests. Files here are generated or edited during the workflow and should not be committed by default (the repo ignores `work/`). Some files like `schema.json` are force‑tracked so downstream tools can bootstrap.

Quickstart
- Create request: `mix spec.new --id <id>` (if available in your setup), or scaffold `work/spec_requests/<id>/request.json` manually using `schema.json` as guidance.
- Discuss via messages: drop JSON message files under `inbox/` or `outbox/` (see `message.schema.json`). Attach artifacts alongside and reference them via relative paths.
- Render thread: `mix spec.thread.render --id <id>` to produce `thread.md` for review.
- Lint request: `mix spec.lint --id <id>` validates request/ack/messages and attachments, and renders the thread.
- Apply proposals: `mix spec.apply --id <id> [--source inbox|outbox] [--target /path/to/repo]` applies `patch.json` attachments onto target files.
- Bundle for handoff: `mix spec.bundle --id <id>` creates `work/bundles/<id>.zip` (excludes `thread.md`).
- Unbundle: `mix spec.unbundle --zip work/bundles/<id>.zip [--dest .]` extracts the archive preserving paths.
- Export JSON‑LD: `mix spec.export.jsonld --id <id> --project <name> --hub ../lang-spec-hub` writes JSON‑LD documents under the hub.
- Initialize hub: `mix spec.hub.init --dest ../lang-spec-hub` creates hub folders and copies schemas/docs.
- Sync to hub: `mix spec.hub.sync --id <id> --project <name> --hub ../lang-spec-hub` copies the request folder, exports JSON‑LD (unless `--no-export`), and refreshes the hub index (unless `--no-index`).

Schemas & Examples
- `schema.json` — JSON Schema for `request.json` (force‑tracked).
- `ack.schema.json`, `message.schema.json` — validation for ack and messages.
- `ack.example.json` — template for acknowledgements.

Notes
- The `work/` directory is ignored by Git to prevent accidental commits of large or transient artifacts. Use bundles or hub sync for sharing.
- If you add new generator tasks, keep this README brief and link to project docs as needed.

