# GymLog — voice-first workout logger

Implementation of `gym_log_app_spec_v0.2.md`.
**Status:** core logic verified (38 passing tests) + full iOS app layer written.
**New here?** Read `WINDOWS_SETUP.md` for the complete Windows dev environment guide.

## Layout

```
GymLog/
├── WINDOWS_SETUP.md            ← how to develop iPhone apps from this Windows PC
├── CoreLogic/                  ← Swift Package: platform-independent, TESTED (38/38)
│   ├── Sources/GymLogCore/
│   │   ├── Models.swift            SetDraft, ParseResult, units (§7.5)
│   │   ├── NumberNormalizer.swift  spoken text → tokens, plate-math (§7.4)
│   │   ├── SetParser.swift         order-independent slot filling (§7.5)
│   │   ├── ExerciseCatalog.swift   24-exercise seed + alias/fuzzy matching
│   │   ├── WorkoutRecords.swift    session/routine value models + starter templates (§8)
│   │   ├── AnalyticsCalculator.swift  volume, e1RM (Epley), periods (§12)
│   │   └── ExportService.swift     Markdown + CSV export (§15)
│   └── Tests/GymLogCoreTests/      §17 corpus — grow with every real mis-parse
└── iOSApp/                     ← the app target (needs Xcode on a Mac, or xtool)
    ├── App/GymLogApp.swift             @main, root TabView (§5), toast overlay
    ├── Intents/LogSetIntent.swift      Action Button / Siri (§7.2)
    ├── Services/SpeechService.swift    on-device SFSpeechRecognizer (§7.3)
    ├── Services/SessionCoordinator.swift  §7.6 state machine, §11 rest timer,
    │                                      autosave + crash recovery, routines CRUD
    ├── Services/PersistenceController.swift  programmatic Core Data model (§8),
    │                                      NSFileProtectionComplete (§10)
    └── Features/
        ├── Workout/WorkoutView.swift       live view: cards, timers, mic, undo (§6.1)
        ├── VoiceCapture/VoiceCaptureView.swift  overlay, chip, suggestions (§6.2, §7.7)
        ├── Routines/RoutineViews.swift     list + builder + picker (§6.3)
        ├── Dashboard/DashboardView.swift   Swift Charts, summaries, history (§6.4, §12)
        └── Profile/ProfileView.swift       settings, export share, iCloud KV prefs (§6.5)
```

## Run the tested core (any platform with Swift 5.9+)

```bash
cd CoreLogic
swift test        # 38 tests: parser corpus, normalizer, analytics, export
```

### Or with Docker (no local Swift install needed)

The `Dockerfile` packages the Swift 5.10 toolchain + GymLogCore, so any work
environment with Docker can build and test the core identically:

```bash
docker build -t gymlog-core .      # resolves deps, compiles the package
docker run --rm gymlog-core        # runs the full test suite
# or, via compose:
docker compose run --rm test       # same as above
docker compose run --rm dev        # interactive shell, live-mounted source
```

Note: only `CoreLogic/` is containerizable — the `iOSApp/` target still
requires Xcode on a Mac (or the WSL2 + xtool route in `WINDOWS_SETUP.md`).

On this Windows PC, Docker runs inside WSL2 Ubuntu (`wsl -u sly`), not on
Windows itself — run the commands above from a WSL shell.

## CI — verification without a Mac

| Workflow | Trigger | What it proves |
|---|---|---|
| `core-tests.yml` (ubuntu) | every push / PR | Docker image builds; all 38 core tests pass |
| `ios-build.yml` (macos-15) | manual: Actions → Run workflow | the app compiles with real Xcode against the iOS Simulator SDK |

The iOS workflow generates `GymLog.xcodeproj` on the runner from
`project.yml` (XcodeGen) — the project file is never committed. It is
dispatch-only because this repo is private and macOS minutes bill at 10×;
run it when iOS-layer code changes.

## Building the app itself

Two routes — both detailed step-by-step in `WINDOWS_SETUP.md`:
1. **From this Windows PC:** WSL2 + xtool → builds, signs, installs to a
   USB-connected iPhone (free Apple ID, 7-day resign cycle).
2. **On a Mac (eventually required for App Store):** Xcode → new iOS 17 SwiftUI
   project "GymLog" → add `CoreLogic` as a local package → drag in `iOSApp/`
   folders → add mic + speech Info.plist usage strings → run on device →
   assign the "Log a Set" shortcut to the Action Button.

## What's implemented vs the spec

| Spec area | Status |
|---|---|
| §7 voice pipeline (normalize → parse → commit) | ✅ built + unit-tested |
| §7.2 Action Button / Siri App Intent | ✅ written (device-verify pending) |
| §7.6 state machine, §7.7 confirm/undo/errors | ✅ |
| §8 data model, §10 file protection, autosave/crash-resume | ✅ programmatic Core Data |
| §6.1–6.5 all five screens | ✅ SwiftUI |
| §11 rest timer (live + recorded, capped) | ✅ |
| §12 analytics + §6.4 charts | ✅ math tested; charts written |
| §15 export (Markdown/CSV) | ✅ tested |
| US-4 routines + starter templates | ✅ |
| §13 StoreKit paywall, §14 Crashlytics, HealthKit | ⏳ post-alpha per roadmap |

## Open decisions currently hard-coded

| Spec flag | Current choice | Where |
|---|---|---|
| [OPEN A] | auto-start "Untitled" session | `SessionCoordinator.ensureActiveWorkout` |
| [OPEN C] | >50 = weight; both ≤30 = ask again; else weight-then-reps | `SetParser.resolveUnlabeled` |
| [OPEN E] | reject weight-only by default; Settings toggle flips it | `ParserPrefs.allowWeightOnlyDraft` |
| [OPEN G] | iOS 17 deployment floor | Xcode project setting |
