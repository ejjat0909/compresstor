# Compresstor Stack Migration Plan — Flutter Frontend + Python Engine

Status: DRAFT (proposal — no code changed yet)
Date: 2026-08-03
Scope: migrate the UI layer from PySide6 to Flutter; keep the compression
engine in Python. This document lists the phases, decisions, and exit
criteria. It does not execute any of them.

## 1a. Pinned toolchain

- **Flutter 3.44.6** (stable, desktop enabled) + its bundled Dart SDK — the
  single pinned version for the frontend across dev, CI, and packaging.
  `pubspec.lock` is committed to lock SDK/package resolution. Sub-agents and
  any machine building the app must use exactly 3.44.6; record
  `flutter --version` in docs/adr/ at Phase 0.

---

## 1. Goal

Replace the PySide6 presentation layer with a Flutter desktop frontend while
keeping the Python compression engine (PyMuPDF + Pillow) as the backend.

Target architecture:

    +----------------------------+      JSON over     +-------------------------------+
    |  Flutter desktop app       |  <--------------> |  Python engine sidecar        |
    |  (UI: dashboard/history/   |   stdin/stdout    |  engine_cli.py -> use_cases   |
    |   settings, theming, drag- |   (or localhost   |  -> compressors -> PyMuPDF/   |
    |   drop, file dialogs)      |    HTTP option)   |   Pillow -> json_stores)      |
    +----------------------------+                   +-------------------------------+
                macOS .app / Windows .exe              bundled via PyInstaller

What survives untouched (the whole engine):
  - app/core/ (entities.py, ports.py, use_cases.py — already Qt-free)
  - app/adapters/compressors/ (pdf_compressor, image_compressor, registry, target)
  - app/adapters/storage/json_stores.py (settings + history persistence)
  - tests/test_compressors.py (16 tests, pure logic — no UI involved)

What gets rewritten: app/presentation/ (PySide6) -> Flutter app.

---

## 2. Open decision — engine transport (must be locked in Phase 0)

| Option              | How it works                            | Pros                                          | Cons                                        | Verdict |
|---------------------|-----------------------------------------|-----------------------------------------------|---------------------------------------------|---------|
| A. CLI subprocess   | Flutter spawns `engine_cli.py`; JSON    | No ports, no server lifecycle, trivial        | Progress = stdout lines to parse;           | RECOM-  |
| (stdin/stdout)      | request on stdin, JSON-lines events on  | kill/cancel, smallest footprint, works        | must design line protocol carefully;        | MENDED  |
|                     | stdout; one request per invocation      | offline; reuses current engine 1:1            | per-run process spawn (~0.5-1s PyMuPDF     |         |
|                     |                                         |                                               | import cost)                                |         |
| B. Local HTTP       | Flutter starts `uvicorn engine_server`  | Clean request/response, SSE for progress,    | Ships a web server per app instance,       | Fallback|
| (FastAPI, localhost)| on a random port; REST + SSE            | easier to debug with curl, streaming is      | port management, bigger bundle, more       | if      |
|                     |                                         | first-class                                 | moving parts                               | A proves|
|                     |                                         |                                               |                                            | awkward |
| C. Persistent CLI   | One long-lived engine process; JSON     | No per-run import cost, supports a `cancel`  | State machine to manage (idle/running/     | Revisit |
| (keep-alive)        | framed messages both ways               | command mid-run, progress via events          | exiting), framing protocol, crash recovery  | after A |
| D. Hosted backend   | Real server; files uploaded to it       | Mobile/web UI possible later                 | PDFs leave the machine, new product,       | Out of  |
|                     |                                         |                                               | infra cost                                  | scope   |

Recommendation: start with **A (CLI subprocess)** — smallest risk, reuses the
engine 1:1, and the core architecture already treats the engine as a
framework-agnostic service. If per-run startup cost is annoying in practice,
upgrade to **C (persistent process)** later without touching the UI.

---

## 3. What changes vs. what stays

| Layer                    | Today (PySide6)              | After migration                     |
|--------------------------|------------------------------|-------------------------------------|
| app/core                 | Python, Qt-free              | UNCHANGED                           |
| app/adapters/compressors | Python                       | UNCHANGED                           |
| app/adapters/storage     | Python (JSON stores)         | UNCHANGED (engine keeps owning data)|
| tests                    | pytest, 16 tests             | UNCHANGED + new engine_cli tests    |
| engine entry point       | main.py (Qt app)             | NEW engine_cli.py / engine_server.py|
| UI                       | PySide6 presentation layer   | NEW Flutter app (replaces it)       |
| UI tests                 | qa_screenshot.py (visual QA) | NEW Dart unit/widget + integration  |
| Packaging                | PyInstaller single bundle    | PyInstaller sidecar + Flutter bundle|
| Build scripts            | build_macos.sh, build_windows.bat | REWRITTEN (sidecar first, then app)|

---

## 4. Phases

### Phase 0 — Decision & spike (0.5-1 week)
Lock the transport choice and prove the end-to-end path before any real UI work.
- [ ] Prototype: hand-written `engine_cli.py` exposing `compress`, `history`,
      `settings` subcommands over JSON; run one real PDF + one image through it.
- [ ] Hello-world Flutter macOS app that spawns the CLI, sends a compress
      request, renders progress lines, shows the result file.
- [ ] Measure: engine import + compress latency for a 10 MB PDF (informs
      Option A vs C).
- [ ] Lock decision from section 2; write ADR entry in repo (docs/adr/).
- [ ] Install/verify toolchain: **Flutter 3.44.6** (stable, macOS arm64) with its
      bundled Dart SDK, CocoaPods if needed. Record `flutter --version` output
      in the ADR so the pinned toolchain is auditable.
Exit: end-to-end PDF compressed through Flutter 3.44.6 -> CLI -> PyMuPDF with a
working progress event.

### Phase 1 — Engine CLI (1 week)
Turn the prototype into the real engine backend.
- [ ] `engine_cli.py` (or `engine_server.py` if B/C chosen) in repo root or
      `app/engine/`:
      - `compress`: accepts FileItem list + CompressionOptions (JSON), streams
        per-file progress events, returns JobResult list; honours a `cancel`
        flag (new `should_cancel` wiring on stdin for option C).
      - `history list|add|clear|remove` -> HistoryUseCase + json_stores.
      - `settings get|set` -> SettingsUseCase + json_stores.
- [ ] Schema: one JSON request per line in, one JSON event per line out;
      document field names in `docs/engine-protocol.md`.
- [ ] `app/core/ports.py`: add `CancellationToken`-style hook if needed for C.
- [ ] New tests: `tests/test_engine_cli.py` (request/response, error paths,
      malformed JSON, cancel mid-batch). All 16 existing tests still pass.
- [ ] Update `scripts/qa_screenshot.py` to ALSO exercise the CLI (engine QA
      without a GUI).
Exit: CLI can fully drive compress + history + settings; test suite green.

### Phase 2 — Flutter scaffold & design system (1 week)
- [ ] `flutter create` app in `flutter/` subfolder (org: com.ejjat0909.compresstor)
      using **Flutter 3.44.6**; commit `pubspec.lock` so the toolchain version is
      locked for every contributor/CI run.
- [ ] Port the design tokens: `app/presentation/theme/palette.py` + styles.py
      -> Dart `lib/theme/` (colors, spacing, radii, typography — Inter bundled,
      Lucide-style icons -> use `flutter_icons`/material symbols or bundled SVGs).
- [ ] Dark theme (app is dark-only since 2026-08 — mirror current look exactly).
- [ ] Widget library skeleton mirroring components/: Button, Badge, Card,
      Dropdown, Input, Switch, Modal, Toast, Progress, Sidebar, Tabs,
      UploadArea, FileTable, ContextMenu, Tooltip, Breadcrumbs, Accordion.
- [ ] App shell: sidebar navigation (Dashboard / History / Settings) with the
      same labels and layout as the PySide6 app.
Exit: shell + themed components render; visual diff vs qa_screenshot output.

### Phase 3 — Dashboard (1-1.5 weeks)
Port `dashboard_page.py` + `uploadarea.py` + `filetable.py`.
- [x] Drag-and-drop + "Add files" picker (file_selector / file_picker pkg) with
      same accept rules (PDF_EXTENSIONS + IMAGE_EXTENSIONS, reject others as
      "Unsupported file type").
- [x] File queue table: name, kind badge, size, status (pending/running/done/
      failed/skipped), per-row remove; chips for selections, no truncation
      (match existing row style: no dividers, compact padding).
- [x] Compression options panel: level presets (High/Balanced/Maximum),
      output mode (suffix/directory/overwrite), suffix field, max-size MB,
      overwrite confirmation toggle — exact labels from the PySide6 settings.
- [x] Compression actions: Run (spawns engine), Cancel mid-run, progress bar
      + per-file status streamed from engine events.
Exit: a full batch compresses through the engine with live progress and
correct output paths (resolve_output_path logic stays in Python).

### Phase 4 — History & Settings (1 week)
- [x] History page: list from engine `history list` (limit 200), columns
      mirroring history_page.py, per-row actions (open file, remove, clear all).
- [x] Settings page: accent color, history limit, default level/output mode,
      overwrite confirmation, add-to-history — persisted via engine
      `settings set`.
- [x] App settings loaded at startup from engine, applied to theme.
Exit: history and settings behave identically to the PySide6 app (compare
against qa_screenshot render).

### Phase 5 — Dart tests & engine parity suite (1 week)
- [x] Unit: option <-> JSON mapping, event parsing, state reducers.
      (`test/engine_models_test.dart`, `test/engine_client_test.dart` against a
      fake engine fixture, `test/format_test.dart`, `test/app_controller_test.dart`)
- [x] Widget: dashboard, history, settings widget tests (flutter_test) incl. the
      save/reset flows on settings and the row-actions menu on history.
- [x] Integration (`integration_test/compression_flow_test.dart`): a full batch
      compresses through the REAL engine (PyMuPDF/Pillow) driven via the UI —
      asserts output file exists, size shrank, and a history row was added
      (`flutter test integration_test/compression_flow_test.dart -d macos`).
- [x] Parity checklist: same fixtures through the OLD engine path
      (`CompressUseCase(CompressorRegistry())` — what PySide6 wired) and the
      NEW CLI (`engine_cli.py compress`, what Flutter spawns) produce IDENTICAL
      output sizes (`scripts/parity_check.py` → `docs/parity-report.md`,
      guarded by `tests/test_parity.py`). Byte-identical outputs additionally
      for deterministic formats (JPEG/WebP/TIFF); PDFs (random /ID per save)
      and low-quality PNGs (randomized Floyd–Steinberg dither) are size-only
      by design.
Exit: `flutter test` (61) + `flutter test integration_test` green; pytest 38
green; parity table shows identical compressed sizes.

Phase 5 discoveries (recorded for Phase 6):
- The macOS **App Sandbox is incompatible with the Python sidecar**: the
  interpreter shells out to `xcrun` at startup, which the sandbox blocks
  ("xcrun: error: cannot be used within an App Sandbox"), breaking the engine
  subprocess. App Sandbox is now disabled in `DebugProfile.entitlements` (debug
  + `flutter test integration_test`), kept in `Release.entitlements`. Bundling
  a sandbox-compatible sidecar is a Phase 6 packaging task.
- `flutter test integration_test -d macos` needs an interactive GUI session to
  foreground the app; run it from a desktop login, not a headless/SSH shell.

### Phase 6 — Packaging (1-2 weeks)
- [x] Sidecar build: `packaging/engine.spec` — lean PyInstaller spec, engine
      only, NO Qt (PyMuPDF/Pillow, numpy excluded). Produces a one-folder
      `dist/engine_cli/` that runs headless. **arm64 verified.** universal2
      needs a lipo-merged universal venv (`scripts/merge_universal_venv.sh`,
      documented below) — not built on this arm64-only machine.
- [x] Flutter build: `flutter build macos --release` — the `.app` is a
      universal2 binary (Xcode builds both archs). Sidecar is bundled into
      `<app>/Contents/Resources/engine/`; `EngineClient` resolves the bundled
      engine at runtime (`bundledEngineFor`) and falls back to the dev venv in
      development/`flutter test`.
- [x] Signing/notarization: ad-hoc deep re-sign of the bundle after bundling
      (`codesign --force --deep --sign -`); `codesign --verify` clean. First
      launch needs right-click → Open (same as v1.0.0).
- [x] Replace `build_macos.sh` / `build_windows.bat` with two-stage scripts
      (sidecar, then Flutter app, then bundle+sign); keep `release/` layout.
      macOS fully exercised; `.bat` written but must be run on Windows.
- [x] Exit criterion met on this machine: `release/MacOS/Compresstor.app`
      compresses a file through the bundled engine with NO dev Python.

Phase 6 follow-ups (not done here):
- **universal2 engine** for Intel Macs: the Flutter `.app` is already
  universal, but the sidecar is host-arch (arm64). Build the engine from a
  python.org universal2 Python 3.11 venv, lipo-merge the x86_64 PyMuPDF/Pillow
  wheels into it (`scripts/merge_universal_venv.sh`), then
  `COMPRESSTOR_ARCH=universal2` PyInstaller. Until then the new app runs on
  Apple Silicon only; the old universal `release/MacOS/Compresstor-1.0.0.dmg`
  remains for Intel during the Phase 7 transition.
- **Windows build** is scripted but unverified (no Windows machine here).
- **Sandbox**: removed from BOTH DebugProfile and Release entitlements — the
  sidecar needs unrestricted file access and v1.0.0 shipped unsandboxed. A
  sandboxed App-Store build would be a separate, larger effort.
- **Notarization** (Developer ID + notarytool) is left to release time (needs
  an Apple Developer account / signing identity).

### Phase 7 — Parallel run, QA & cleanup (1 week)
- [ ] Ship new app as the default; keep old release/MacOS/Compresstor.app
      available for a/b during the transition.
- [ ] Full visual QA pass (qa_screenshot.py on engine side + Flutter golden
      renders), fix alignment/padding/chip-overflow nits on first pass.
- [ ] README update: new build instructions, architecture diagram.
- [ ] Remove app/presentation/ + PySide6 deps from requirements.txt only after
      parity confirmed. main.py becomes the engine entry point (or is
      removed if engine_cli owns it).
Exit: new app is the only shipped artifact; PySide6 fully removed; all tests
green.

---

## 5. Key risks & mitigations

| Risk                                   | Mitigation                                   |
|----------------------------------------|----------------------------------------------|
| IPC protocol design churn              | Phase 0 spike + docs/engine-protocol.md      |
| Sidecar packaging regression (lipo,    | Reuse documented gotchas; leaner spec (no    |
| re-sign, taskgated)                    | Qt); CI-less but scripted build from scratch |
| Compression parity drift                | Same engine code path; parity table in Phase 5|
| Flutter desktop gaps (file dialogs,    | Verify in Phase 0 spike before committing    |
| drag-drop, tray)                       |                                              |
| Double runtime size (~150-250 MB)      | Accepted trade-off; document in README       |
| Two-language maintenance burden        | Engine owns all logic; Dart stays thin UI    |

## 6. Definition of Done (whole migration)

- [ ] Flutter app compresses PDFs + images with results identical to the
      PySide6 app (same engine, same options).
- [ ] History and settings survive app restarts (engine-owned JSON stores).
- [ ] All 16 engine tests + new CLI tests + Dart tests pass.
- [ ] Installable macOS universal2 .app and Windows .exe on clean machines.
- [ ] PySide6 removed from the repo; README + docs updated.

## 7. Rough timeline

  Phase 0 spike ....... 0.5-1 wk
  Phase 1 engine CLI .. 1 wk
  Phase 2 scaffold ..... 1 wk
  Phase 3 dashboard .... 1-1.5 wk
  Phase 4 history/set .. 1 wk
  Phase 5 tests/parity . 1 wk
  Phase 6 packaging .... 1-2 wk
  Phase 7 cleanup ...... 1 wk
  Total ................ ~7-9.5 weeks part-time

## 8. Open questions for Izzat (decide before Phase 0)

1. Transport: confirm Option A (CLI subprocess) as default? (recommended)
2. Keep engine-owned persistence (history/settings stay in Python JSON
   stores), or move them to Dart-side storage later? (recommended: engine)
3. Is the macOS-only target still the priority, or is Windows parity required
   in the same release?
4. Any UI redesign goals beyond a 1:1 port (e.g. new layout, tray icon,
   keyboard shortcuts), or strict visual parity first?
