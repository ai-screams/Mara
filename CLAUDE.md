# Mara — Claude Code notes

## Build & test

- `scripts/generate-project.sh` is a required first step — `Mara.xcodeproj` is generated (gitignored),
  and the helper restores the committed SwiftPM revision lock. `make test|generate|build|release`.
- Single test: `cd MaraCore && swift test --filter <TestName>`.
- Local smoke test: after a Release build, always re-sign with an Apple Development identity (no ad-hoc — global rule).
  Look up identities: `security find-identity -v -p codesigning` (use the Apple Development entry).
  Re-sign Sparkle's nested code inside-out first: Frameworks' `*.xpc`/`Autoupdate` → `Sparkle.framework` → the app.
- The proper way to sign a local run is to **build with signing from the start**: `xcodebuild … CODE_SIGN_STYLE=Manual
  "CODE_SIGN_IDENTITY=Developer ID Application" DEVELOPMENT_TEAM=7K6MK3KP9K build` — xcodebuild signs the nested Sparkle
  correctly too (the inside-out manual re-sign above is only for re-signing an already-built artifact after the fact).
  Apple Development "automatic" signing fails on this Mac (no Xcode account for that team) — use the same
  Developer ID (7K6MK3KP9K) as the running app and release.sh.
- Before swapping the running app: check `pgrep -x Mara` → `osascript -e 'tell application "Mara" to quit'` →
  **re-check pgrep after quit** (quit can return before termination completes — a duplicate instance killing the
  live Mara was a real incident) → swap → `open`.
- If a local Release rebuild fails with `"Operation not permitted"` (copying AppIcon.icns, etc.) on top of an
  **existing signed bundle**, App Management TCC is blocking **in-place modification** of the signed `.app`
  (not the uchg flag). The proper fix = `rm -rf` the stale bundle (deletion is allowed — not a bypass) then do a
  **clean rebuild** (quit first if it's running). One real incident (during a B→C deploy).
- Safer proper approach: do local App builds/smoke tests with an **isolated `-derivedDataPath` (scratchpad)** — it
  doesn't touch the shared DerivedData (`~/Library/.../Products/Release/Mara.app`) where the live Mara runs, avoiding
  both the TCC in-place block above and live-app corruption at once. Only after **build success + symbol verification**
  in the isolated build: quit → check pgrep → swap (zero downtime; never swap before verification).
- Before installing a QA build, **verify symbols in the artifact**: confirm `grep -c -a '<new selector/type name>' <APP>/Contents/MacOS/Mara` ≥1, then install.
  Subagents build to their own derivedDataPath, so the artifact on the controller's path may be stale (one real incident).
  Strings containing Unicode ("Custom…" etc.) won't be caught by strings|grep — search by ASCII symbol name.
  In an optimized (-O) Release, even short strings (≤15B, e.g. "Icon Color") get inlined as Swift SmallString and
  aren't found by grep — they survive in Debug (`.debug.dylib`), but for Release verify via selector/type names
  (`setMenuBarTint`·`MenuBarTint`) (one real incident).
  Debug builds keep the code in `Mara.debug.dylib` while `Contents/MacOS/Mara` is a thin launcher — grep Debug symbols
  against `.debug.dylib` (or `grep -r` the MacOS directory). Grepping only the thin launcher gives a false 0 (one real incident).
- Run xcodebuild·git from the repo root — cwd persists across shell calls and is inherited by background jobs (staying
  in MaraCore and running nothing was a real incident). A pipe (`| tail`) swallows the exit code, so judge compile
  verification by checking for the "BUILD SUCCEEDED" string.
- Core `swift test` does not verify App (AppKit/SwiftUI) compilation — when adding a case to a Core enum (e.g.
  `SessionFailure`) or changing App files, always confirm with an App strict build. Missing `switch` cases and broken
  SwiftUI are only caught here: `xcodebuild … CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build` → confirm "BUILD SUCCEEDED".
- The per-file coverage gate (`scripts/coverage.sh` → `coverage_file_gate.py`) is **CI-only** (`make test` doesn't run it).
  OS-adapter files like IOKit measure lower than local on the headless CI runner because hardware-dependent branches
  don't execute — real incident: `BatteryMonitoring.swift` local 84% / CI 73.2%, hitting the 75% floor. **The proper
  fix is not to lower the floor but to separate the pure logic from the OS calls and unit-test it** — splitting
  `IOKitBatteryMonitor.parse(_:)` out of `read()` passed CI at 80.2%. Verification tip: run only
  `swift test --filter <pure test>` so the IOKit path executes 0 times; if the pure function body is then covered,
  that's proof it's covered in CI too.

## Architecture (placement rules)

- Logic and decisions live in `MaraCore/` (OS-free, behind protocols, testable) — the App is a thin AppKit shell.
  Dependency direction is App→Core only (one-way).
- When adding an OS adapter: define the protocol in Core → instantiate and inject from the App (`AppEnvironment`)
  (same pattern as the existing Battery/Screen/Apps/Network).
- `@Published` fires on willSet — don't re-read in the sink; use the emitted value directly (see existing code comments).
- Core operations (`SessionManager.start`/`stop`/`toggle`/`updateScope`) return `Result<_, SessionFailure>` and change
  state only after the side effects (applying/releasing assertions) are confirmed (`SleepEngine.apply` one level down
  returns `Result<_, SleepEngineFailure>` — SessionManager wraps it as `.power(_)`). The App layer
  (`SessionFailureText`) maps failures to text — don't put UI strings in Core (same as the existing rule).
- When passing click-time data to a SwiftUI sheet, use `.sheet(item:)` — isPresented + a separate @State captures
  stale (empty) state on first presentation (real incident: empty picker — surfaced only on a real device after
  passing review 4 times; see the RunningAppPicker comment).
- `BatterySnapshot.isOnAC` is `false` even for `.unavailable` — decide the low-battery veto by `case .battery(...)`
  pattern matching, not `!snap.isOnAC` (otherwise every session start is wrongly rejected on a desktop / when the IOPS
  read fails). See `SessionManager.batteryFloorBreach`; pinned by tests.

## Release (CI is canonical)

- Tag push (vX.Y.Z) → protected `release` environment. Approval: UI or `gh api repos/…/actions/runs/<id>/pending_deployments`.
  For CLI approval, `-F "environment_ids[]=<id>"` — it's an integer field so `-F` is required (`-f` sends a string → 422, one real incident).
- Release notes are auto-generated from PR titles by release.yml's `generate_release_notes` (already in place).
  Adopting a release-please-style tool is deferred pending review — rationale and re-evaluation conditions in BACKLOG.md.
- The version source of truth is the git tag: release.sh overwrites MARKETING_VERSION with the tag (the project.yml
  value is dev-only). CFBundleVersion = git commit count (monotonic) — no consecutive tags without a commit in between.
- v* tags are immutable via ruleset — a failed release can't reuse the tag; recover with a patch bump (RELEASING.md).
- Before pushing a tag (immutable), preflight the pipeline: `git diff --stat v<previous>..HEAD -- .github/workflows/release.yml
  scripts/release.sh App/Info.plist project.yml` — if empty, the release path is byte-identical to the last successful one (minimal failure risk).
- **Verify with the published artifact**: `gh release download` → check spctl/stapler/appcast/`.background`.
  Local-reproduction verification has been wrong twice in this repo (menu-bar orange, DMG background).
- When verifying the appcast, `sparkle:version` is a **child element** (`<sparkle:version>N</sparkle:version>`), not an
  attribute — an attribute grep (`sparkle:version="…"`) returns empty. Same for shortVersionString. Only edSignature is an enclosure attribute.
- `scripts/release.sh` is **zsh**: `${VAR:+--flag "$VAR"}` is not word-split — build arguments as an array.
- codesign signature verification: the Hardened Runtime signal is `flags=…(runtime)` (a CodeDirectory flag), not
  `Runtime Version=` (the SDK version). The leaf cert is `Authority=Developer ID Application`; `…Certification Authority` is the intermediate CA.
- Polling PR CI status: don't parse the tabbed output of `gh pr checks` with `awk '{print $2}'` — the space in the
  check name "Build & Test" shifts the fields so the status reads as "&", causing an **early exit** (two real incidents).
  Use `gh pr view <n> --json statusCheckRollup` instead, but note that while running `.conclusion` is not null but an
  **empty string**, so a jq `// "RUNNING"` fallback doesn't kick in — judge completion by `.status=="COMPLETED"`.
- Local notarization: don't put the password on argv — use `NOTARY_PROFILE=mara-notary` (Keychain profile).

## macOS 26 menu-bar quirks (details in auto-memory · code comments)

- The ground truth for render verification is the user's screenshot / occlusionState — API values (isVisible, tint) lie.
- The ground truth for notification permission is a delivered banner — delivery can succeed even when the app isn't in `com.apple.ncprefs.plist`.

## Conventions

- UI strings are in English. Code comments are in Korean (memory-safety / network-parser code is in English).
- The backlog is `.docs/BACKLOG.md` (`.docs` must never be committed — same as the global rule). Specs/plans also live in `.docs/`.
- When dispatching reviews/audits (subagents / Codex), spell out the design decisions the user has settled on in the
  prompt — a context-less auditor reports intended decisions as defects (one real incident).
