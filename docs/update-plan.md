# Update Check & Auto-Update — Implementation Plan (macOS + Windows)

> Status: IMPLEMENTED — on branch `feature/auto-update` (Tasks 1–6, TDD, one
> commit each). UI + updater done; outstanding (user-run): publish a real
> GitHub release, in-app click-through, Windows build verification.
>
> **Decision (confirmed): update source = GitHub Releases (Option A).**
> The client is built against the generic `UpdateSource` abstraction so an
> own-server (Option B) stays possible later without an app change.

## Goal

Give the Settings → **About** card a manual "Check for updates" flow:
the app reads its own version from a single `version.json` file, compares it
with the latest published version, and — when the user clicks **Update** —
downloads, verifies, and replaces itself, then relaunches. Works on macOS and
Windows. The engine sidecar (Python) travels inside the app on both platforms,
so replacing the app replaces the engine too.

---

## 1. Where the version lives today (and what changes)

Today the version is hardcoded in two unrelated places:

| Where                                        | Value                         | Used for                                                                                     |
| -------------------------------------------- | ----------------------------- | -------------------------------------------------------------------------------------------- |
| `flutter/pubspec.yaml` line 19             | `version: 1.0.0+1`          | CFBundleShortVersionString (macOS) / Windows product version — set at`flutter build` time |
| `flutter/lib/pages/settings_page.dart:294` | `Text('Compresstor 1.0.0')` | What the About card displays                                                                 |

That is exactly why "I don't know where to change the version" — there are two
places, they can drift, and neither is readable by the app at runtime.

**New model — one file to edit:**

```
repo root/version.json          ← THE version. You edit ONLY this file.
```

```json
{ "name": "compresstor", "version": "1.0.0", "build": 1 }
```

- **Bump = edit `version.json`.** Nothing else.
- The build scripts read it and pass `--build-name 1.0.1 --build-number 2` to
  `flutter build`, and copy it into the bundle so the app can read it at runtime:
  - macOS: `Compresstor.app/Contents/Resources/version.json`
  - Windows: `<exe dir>\version.json`
- The About card reads the bundled `version.json` (via Flutter asset) and shows
  **Version 1.0.1** — never hardcoded again.
- Dev mode (`flutter run`) reads the committed copy of the same file
  (`flutter/assets/version.json`, kept in sync by the build script).

---

## 2. UI walkthrough — Settings → About

Navigation: **Settings** (sidebar) → **About** card (first card, top of the
page — above Save/Reset buttons).

### Idle state (today, + version read from file)

```
┌─ About ────────────────────────────────────────┐
│ Compresstor                                    │
│ Version 1.0.0                                  │   ← from version.json
│ Compresses PDF and image files entirely on     │
│ your device. Files never leave your computer.  │
│                                                │
│ [ Check for updates ]                          │   ← ghost button, new
└────────────────────────────────────────────────┘
```

### After clicking "Check for updates"

| Outcome      | What the user sees                                                                                                                |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| Checking…   | Button shows a small spinner, label stays**Check for updates**, disabled                                                    |
| Up to date   | Success toast**You're up to date** + caption under the button: `You're running the latest version (1.0.0).`               |
| New version  | Row appears:**Version 1.0.1 is available** + release-note caption (1 line, truncated) + primary button **[ Update ]** |
| Check failed | Danger toast**Couldn't check for updates** + caption: `Check your internet connection and try again.`                     |

### Update-available state (ASCII)

```
┌─ About ────────────────────────────────────────┐
│ Compresstor                                    │
│ Version 1.0.0                                  │
│ Compresses PDF and image files entirely on     │
│ your device. Files never leave your computer.  │
│                                                │
│ Version 1.0.1 is available                     │
│ New: faster PDF engine, bug fixes.             │
│ [ Update ]                                     │   ← primary button
└────────────────────────────────────────────────┘
```

### While updating (clicked Update)

The **Update** button turns into progress and is disabled:

```
│ Version 1.0.1 is available                     │
│ [ ▓▓▓▓▓░░░░░ 42% ]  Downloading…              │
│ [ ▓▓▓▓▓▓▓▓▓▓ 100% ]  Installing… (restarting)  │
```

On success the app relaunches itself (brief flash — normal). On failure a
danger toast explains why (download failed / checksum mismatch / not enough
permissions), temp files are cleaned up, and the button returns to **Update**
so the user can retry.

> No automatic check on launch (manual only, as requested). Can be added
> later as a settings toggle if wanted.

---

## 3. How "new version" is found — the update source

The app talks to one of two sources (abstraction, so switching is a config
change — a `baseUrl`/`source` constant). **Recommended: GitHub Releases** —
the repo is already on GitHub, zero server setup, no credentials in the app.

### Option A — GitHub Releases (recommended, default)

- Manifest: `GET https://api.github.com/repos/ejjat0909/compresstor/releases/latest`
  (no auth; 60 req/hr unauthenticated is plenty for manual checks).
- Version = release `tag_name` (`v1.0.1` → `1.0.1`).
- Download URLs = release assets (the publish step uploads them):
  - `Compresstor-1.0.1-macos.zip`    → the .app bundle zipped (in-app updater uses this, not the DMG)
  - `Compresstor-1.0.1-windows.zip`  → the whole `release\Windows\Compresstor\` folder zipped
  - `Compresstor-1.0.1.sha256`       → `sha256  <asset name>` lines, one per zip
- Release body (markdown, first line) = release notes shown in the About card.

### Option B — own static server (Plesk, if preferred)

- `https://<your-host>/compresstor/latest.json`:

```json
{
  "version": "1.0.1",
  "build": 2,
  "notes": "New: faster PDF engine, bug fixes.",
  "platforms": {
    "macos":   { "url": "https://<host>/compresstor/Compresstor-1.0.1-macos.zip",   "sha256": "…" },
    "windows": { "url": "https://<host>/compresstor/Compresstor-1.0.1-windows.zip", "sha256": "…" }
  }
}
```

- A `scripts/publish_release.py` builds, zips, hashes, writes `latest.json` and
  uploads everything to the server (rsync/scp).

**Decision needed:** A (GitHub) or B (your server) — see Open Questions.
The plan below implements the client against a generic
`UpdateSource { manifestUrl, artifactFor(platform, version) }` so the choice
only affects the publish script + one config constant.

---

## 4. Update flow (after the user clicks Update)

Both platforms share: download zip → verify SHA-256 → extract to temp →
apply → relaunch. User data is safe by design: settings/history live in
`~/Library/Application Support/Compresstor` (macOS) / `%APPDATA%\Compresstor`
(Windows) — **outside** the app folder, so replacing the app never touches it.

### macOS

1. Download `Compresstor-<ver>-macos.zip` to `<temp>/compresstor-update/`, show progress (content-length).
2. Verify SHA-256 against the manifest (release body / sha256 asset).
3. Extract: `ditto -x -k <zip> <temp>/extracted/` (built-in; preserves permissions).
4. Strip quarantine: `xattr -dr com.apple.quarantine <temp>/extracted/Compresstor.app` (safety for downloaded bundles).
5. Locate the running app: `Platform.resolvedExecutable` → `Contents/MacOS/compresstor` → up 3 = `…/Compresstor.app`.
6. **Swap (CRITICAL — the taskgated rule from the build pipeline):** `rm -rf` the current `.app` FIRST, then `mv` the new `.app` into place. Never copy-over a live bundle.
7. Relaunch: `Process.start(<app>/Contents/MacOS/compresstor, [])`, then `exit(0)`.

### Windows

1–3. Same as macOS (extract via `tar -xf`, available on Win10 21H2+ which the app already requires).
4. Locate the install dir: `Platform.resolvedExecutable` → parent (`…\Compresstor\`).
5. Writable check: try creating+deleting a temp file there. If not writable (e.g. Program Files), danger toast: **Update failed — run Compresstor as administrator to update.**
6. Write `apply_update.bat` into `%TEMP%` (NOT the install dir — the bat must survive the folder swap), then launch it detached: `cmd /c start "" /min <bat>` and `exit(0)`.
7. The bat waits for `compresstor.exe` to exit (`tasklist` loop) → `rmdir /s /q` the install dir → `xcopy /e /i /q` the new folder → `start ""` the new exe → delete itself, logging to `%TEMP%\compresstor-update.log`.

> Why a bat: Windows locks a running exe/DLL, so the app can't replace itself
> in place — the detached helper does the swap after the process exits.

---

## 5. Implementation tasks (TDD, bite-sized)

### Task 1 — `version.json` single source + build-script sync

- Create `version.json` at repo root: `{ "name": "compresstor", "version": "1.0.0", "build": 1 }`.
- Create `flutter/assets/version.json` (same content — committed; build script overwrites it) and add `- assets/version.json` to `pubspec.yaml` assets.
- `scripts/build_macos.sh`: read root `version.json` (python one-liner), pass `--build-name/--build-number` to `flutter build macos --release`, `cp version.json flutter/assets/version.json` before the build, and copy it into `$APP/Contents/Resources/version.json` in Stage 3.
- `scripts/build_windows.bat`: same, copy into the Release dir.
- Verify: build the app, check `Info.plist` CFBundleShortVersionString + bundled file; `flutter test` still green.

### Task 2 — `UpdateClient` (transport) with tests

- Create `flutter/lib/engine/update_client.dart`:
  - `fetchManifest()` → `UpdateManifest { version, build, notes, sha256, downloadUrl }` (parse GitHub API JSON or `latest.json` — one parser, tolerant).
  - `download(url, targetFile, onProgress)` — `http` package, content-length progress, temp file, cleanup on error.
  - `verifySha256(file, expected)`.
  - Injectable `http.Client` (MockClient in tests).
- Tests: `flutter/test/update_client_test.dart` — manifest parse (GitHub + latest.json shapes), version compare (semver: 1.0.1 > 1.0.0, build tiebreak), download+hash verify OK, hash mismatch fails, HTTP error surfaces.

### Task 3 — `UpdateController` (state machine)

- Create `flutter/lib/state/update_controller.dart` (`ChangeNotifier`):
  - States: `idle → checking → upToDate | updateAvailable → downloading(progress) → applying → relaunched`; errors go to `error(message)` and return to previous state.
  - Holds current version (read from bundled `version.json` via `rootBundle`, fallback `0.0.0-dev`), the manifest, and the platform artifact.
  - `checkForUpdates()`, `update()` (download → verify → extract → apply via platform strategy).
  - Platform strategies: `macos_applier.dart` / `windows_applier.dart` behind an `UpdateApplier` interface.
- Tests: fake transport + fake applier → state transitions, double-click guard (button disabled while busy), failure paths.

### Task 4 — About card UI (Settings)

- `flutter/lib/pages/settings_page.dart`: replace hardcoded `Text('Compresstor 1.0.0')` with `Version ${controller.version}`; add the **Check for updates** ghost button + the state rows from §2.
- Wire `UpdateController` in (SettingsPage already receives the app controller — extend or pass alongside).
- Widget tests: idle renders version from injected value; check → spinner; up-to-date toast; update-available shows **Update**; click **Update** shows progress; failure shows toast; no pending timers at test end (drainToasts).

### Task 5 — update artifacts in the build pipeline

- `scripts/build_macos.sh`: after the release install, create `release/Compresstor-<ver>-macos.zip` from `release/MacOS/Compresstor.app` (`ditto -c -k`) + `Compresstor-<ver>.sha256` lines.
- `scripts/build_windows.bat`: zip `release\Windows\Compresstor\` → `Compresstor-<ver>-windows.zip` (PowerShell `Compress-Archive`).
- Create `scripts/publish_release.sh` (Option A): `gh release create v<ver> <zips> <sha256>` with the release notes — one command per release.

### Task 6 — end-to-end verification

- Unit/widget: `flutter test` (all green, incl. new files).
- macOS real run: build with a bumped temp version, host the zip locally (or GitHub draft release), run the release app → Check for updates → Update → confirm it relaunches at the new version with settings/history intact.
- Windows: bat-script logic verified by review + a manual run on a Windows box when available (no Windows machine here — flagged as a follow-up, same as the Phase 6 Windows build).

---

## 6. Files touched (summary)

| Action | Path                                                                      |
| ------ | ------------------------------------------------------------------------- |
| Create | `version.json` (repo root)                                              |
| Create | `flutter/assets/version.json`                                           |
| Create | `flutter/lib/engine/update_client.dart`                                 |
| Create | `flutter/lib/state/update_controller.dart`                              |
| Create | `flutter/lib/engine/update_applier_macos.dart`, `…_windows.dart`     |
| Create | `scripts/publish_release.sh`                                            |
| Create | `flutter/test/update_client_test.dart`, `update_controller_test.dart` |
| Modify | `flutter/pubspec.yaml` (`http` dep + asset)                           |
| Modify | `flutter/lib/pages/settings_page.dart` (About card)                     |
| Modify | `flutter/lib/state/app_scope.dart` (wire UpdateController)              |
| Modify | `scripts/build_macos.sh`, `scripts/build_windows.bat`                 |
| Modify | `flutter/test/settings_page_test.dart`                                  |
| Docs   | `README.md` (release flow: bump version.json → build → publish)       |

---

## 7. Risks & tradeoffs

- **macOS signature:** the app is ad-hoc signed; Gatekeeper may flag the freshly downloaded zip if quarantine isn't stripped. Mitigated with `xattr -dr` before launch; if it ever bites, the fix is real notarization (already a listed follow-up).
- **Windows Program Files:** replacing needs write access → pre-flight writable check + admin hint. Per-user install folders (recommended distribution) never hit this.
- **GitHub rate limit** (60/hr unauthenticated) — irrelevant for manual checks; a future "check on launch" would want a server-side manifest (Option B).
- **In-flight update:** button is disabled while downloading/applying; temp dir is unique per run, so a crashed download can't corrupt a later one (old temp cleaned on next attempt).
- **Swap window (macOS):** brief `rm`→`mv` gap while the old app is gone; the window stays open (loaded code) and the relaunch happens right after. Acceptable for a local-file app.
- **Version drift in dev:** `flutter run` reads the committed `flutter/assets/version.json`, which the build script overwrites — only stale after a root bump without a build. Cosmetic.

---

## 8. Open questions (blocking decisions)

1. **Update host:** ~~GitHub Releases (Option A — recommended) or own Plesk server (Option B)?~~
   **DECIDED: GitHub Releases.** Option B dropped from scope; the
   `UpdateSource` abstraction keeps it possible later.
2. **Windows install location:** **DECIDED (default): per-user folder** (no
   admin needed). The writable-check + admin-hint path stays in for users who
   copy the app into Program Files.
3. **Release notes:** **DECIDED (default):** show the GitHub release body's
   first line in the About card.
4. **Naming:** **DECIDED (default):** `Compresstor-<version>-macos.zip` /
   `Compresstor-<version>-windows.zip` + `Compresstor-<version>.sha256`,
   published as GitHub release assets.

Anything in 2–4 you'd rather change, say so before implementation starts;
otherwise the defaults stand.
