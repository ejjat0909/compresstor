# ADR 0001 — Flutter Frontend + Python Engine (CLI Transport)

- Status: ACCEPTED
- Date: 2026-08-03
- Deciders: Izzat
- Related: [stack-migration-plan-flutter.md](../stack-migration-plan-flutter.md)

## Context

The PySide6 presentation layer will be replaced by a Flutter desktop app while
keeping the Python compression engine (PyMuPDF + Pillow) intact. Section 2 of
the migration plan lists four transport options between Flutter and the engine
(A. CLI subprocess, B. Local HTTP, C. Persistent CLI, D. Hosted backend).

## Decision

1. **Frontend toolchain: Flutter 3.44.6** (stable, desktop enabled). Dart SDK is
   the one bundled with that Flutter release. `pubspec.lock` will be committed
   so every contributor/CI machine resolves the same package graph.
2. **Transport: Option A — CLI subprocess.** Flutter spawns `engine_cli.py`
   (via a PyInstaller-produced binary in packaged builds) for each user
   action. Requests are one JSON object on stdin, responses are one JSON
   event per line on stdout (JSON-lines). Rationale:
   - Reuses the existing framework-agnostic engine 1:1.
   - No port/server lifecycle to manage — trivial cancel via process kill.
   - Smallest packaging surface (no bundled web server, no Qt).
   - Per-run PyMuPDF import cost (~0.5–1s) is acceptable; if it becomes
     annoying, we upgrade to Option C (persistent process) without touching
     the UI protocol.
3. **Persistence stays engine-owned.** Settings and history remain in the
   Python JSON stores (`app/adapters/storage/json_stores.py`); the Flutter UI
   reads/writes them via `engine_cli history …` and `engine_cli settings …`.

## Consequences

- The engine gains a new entry point (`app/engine/engine_cli.py`) plus a
  documented protocol (`docs/engine-protocol.md`).
- Packaging becomes two-stage: PyInstaller builds the engine sidecar, then
  Flutter builds the app and bundles the sidecar. The sidecar spec has no
  PySide6, so the bundle is leaner than today.
- The migration is UI-only: `app/core/` and `app/adapters/` do not change.
- If per-invocation startup cost becomes a UX issue we can add a long-lived
  mode later; the JSON schema is designed to be forward-compatible.

## Toolchain audit

Recorded on 2026-08-03 on macOS 26.5.1 (darwin-arm64):

```
Flutter 3.44.6 • channel stable • https://github.com/flutter/flutter.git
Framework • revision ee80f08bbf (4 weeks ago) • 2026-07-08 15:02:06 -0700
Engine • hash d3a3293399556a85388faf8c6f0723a7a5597aa8 (revision 83675ed276) (1 months ago) • 2026-06-30 16:59:03.000Z
Tools • Dart 3.12.2 • DevTools 2.57.0
```

`flutter doctor` — desktop enabled, no issues. macOS-desktop and
windows-desktop flags are enabled globally via `flutter config`.

### Phase 0 latency measurement

Command:

```
time echo '{"items":[{"path":"…/10mb.pdf"}],"options":{"level":"balanced","output_mode":"suffix","suffix":"_probe"},"add_to_history":false}' \
  | python -m app.engine.engine_cli compress
```

On a 10.0 MB PDF (Python 3.11 venv, PyMuPDF 1.28.0):

| Metric                | Value    |
|-----------------------|----------|
| Wall time             | 1.16 s   |
| CPU (user+sys)        | 1.12 s   |
| Output size           | 1.48 MB (14 % of original) |
| Interpreter/imports   | ≈ 0.4 s (measured with a no-op compress) |

Verdict: Option A (per-run subprocess) is acceptable at this scale. Import
overhead is dwarfed by real work for any interactive file. If large-batch UX
suffers, upgrade to Option C without changing the JSON schema.

## Alternatives considered

- **B. Local HTTP (FastAPI):** larger bundle, port management, no clear
  benefit for a desktop app that already spawns one job at a time.
- **C. Persistent CLI:** stronger long-term, but harder to get right on first
  pass (state machine, framing, crash recovery). Kept as future upgrade.
- **D. Hosted backend:** out of scope — Compresstor is offline-first.
