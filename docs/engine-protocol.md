# Engine CLI Protocol

Status: DRAFT v1 (Phase 1 of the Flutter migration)
Owner: `app/engine/engine_cli.py`

## Framing

- **Invocation**: `engine_cli <subcommand> [--json]` — one subcommand per
  process. The frontend spawns one process per user action.
- **Request**: a single JSON object read from stdin until EOF.
- **Response**: one JSON object per line on stdout (JSON-lines). Every line
  is a complete, parseable JSON object with a `type` field. Non-JSON output
  (Python warnings etc.) is silenced or redirected to stderr.
- **Exit code**: `0` on success (including "one file failed inside a batch"
  — per-file failures are reported as events, not process failures); `1`
  when the request itself is malformed or the process cannot start; `2` when
  the user cancelled mid-run.
- **Cancellation**: SIGTERM (or closing stdin, for the persistent-CLI
  upgrade path). Between file boundaries the CLI checks a cancel flag and
  exits with code 2 after emitting a `cancelled` event.

## Subcommands

### `compress`

Request:

```json
{
  "items": [
    {"path": "/abs/path/a.pdf"},
    {"path": "/abs/path/b.jpg"}
  ],
  "options": {
    "level": "balanced",
    "output_mode": "suffix",
    "output_dir": "",
    "suffix": "_compressed",
    "max_size_mb": null,
    "pdf": {"image_quality": 70, "max_image_dpi": 144, "remove_metadata": true, "deflate": true, "garbage": 4},
    "image": {"quality": 72, "resize_max": 0, "preserve_format": true, "strip_metadata": true}
  },
  "add_to_history": true
}
```

- `level` is one of `high | balanced | maximum`. `pdf` and `image` may be
  omitted — the level preset fills them in.
- `output_mode` is `suffix | directory | overwrite`.
- File `kind` is inferred from extension by the engine (no need to send it).
- `add_to_history` (default true) mirrors the setting.

Response events (JSON-lines):

```
{"type":"started","total":2}
{"type":"progress","index":0,"fraction":0.25,"message":"a.pdf — rewriting page 1/4"}
{"type":"file_done","index":0,"result":{...JobResult...}}
{"type":"progress","index":1,"fraction":0.6,"message":"b.jpg — encoding"}
{"type":"file_done","index":1,"result":{...JobResult...}}
{"type":"finished","results":[{...},{...}]}
```

Additional event types:

- `{"type":"error","message":"..."}` — a fatal error before or between files;
  process exits non-zero after this.
- `{"type":"cancelled","completed":N}` — emitted when the CLI observes the
  cancel flag; process exits with code 2.

`JobResult` shape mirrors `app.core.entities.JobResult`:

```json
{
  "path": "/abs/path/a.pdf",
  "name": "a.pdf",
  "kind": "pdf",
  "status": "done",
  "output_path": "/abs/path/a_compressed.pdf",
  "original_size": 10485760,
  "compressed_size": 4194304,
  "error": ""
}
```

### `history`

Subcommands (as JSON `action` field):

- `{"action":"list","limit":200}` → `{"type":"history","entries":[...]}`
- `{"action":"add","entries":[...]}` → `{"type":"ok"}`
- `{"action":"clear"}` → `{"type":"ok"}`
- `{"action":"remove","timestamp":123.0,"output_path":"..."}` → `{"type":"ok"}`

`HistoryEntry` fields match `app.core.entities.HistoryEntry` verbatim.

### `settings`

- `{"action":"get"}` → `{"type":"settings","settings":{...AppSettings...}}`
- `{"action":"set","settings":{...}}` → `{"type":"settings","settings":{...merged...}}`

## Forward compatibility

- Unknown fields in requests are ignored.
- Unknown event `type` values MUST be ignored by the frontend (allows
  additive protocol changes without breaking older UIs).
- Version bumps go in the ADR and this document; there is no version
  handshake in v1 — both sides are shipped together.
