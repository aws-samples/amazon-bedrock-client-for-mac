# Development and validation

The Xcode project is the application entry point. The root Swift package exposes the platform-independent local core for fast regression tests; it is not a second application.

## Source layout

| Directory | Responsibility |
| --- | --- |
| `Sources/Bedrock/App` | App lifecycle, windows, commands, navigation and state |
| `Sources/Bedrock/Core` | Foundation-only models, migration, routing, skills, tools, queues |
| `Sources/Bedrock/Services` | AWS/MCP clients, persistence, attachments and system APIs |
| `Sources/Bedrock/Features` | Feature views and controllers, grouped by responsibility |
| `Sources/Bedrock/UI` | Design system, shared controls, Markdown, media surfaces |
| `Sources/Bedrock/Resources` | Icons, Core Data model, bundled offline resources and notices |
| `Configuration` | Existing app identity, Info.plist, entitlements |

Add or move files in Xcode with the matching target membership, then validate:

```sh
python3 scripts/check-project.py
python3 scripts/validate-documentation.py
```

The validator checks missing/duplicate files, app/test membership, resources, configuration paths, and the production bundle identifier. Moving source directories must not change the app's identity or existing user-data locations.

## Regression suites

For focused changes, run the affected or previously failing suites locally.
To reproduce the complete pipeline used by GitHub:

```sh
python3 scripts/ci.py \
  --artifacts artifacts \
  --derived-data .build/ci-derived \
  --packages .build/ci-packages
```

Full Xcode must be ready to run and the macOS desktop must be unlocked. Pass
`--developer-dir /Applications/Xcode.app/Contents/Developer` to select a toolchain.
This command validates project membership, documentation, scripts, portable core,
protocol fixtures, pinned dependencies, native rendering, app integration, and
actual UI interactions. The app uses Release `-O` optimization. Each stage must
pass; skipped optional public-network tests are reported separately.

Use a fresh artifact directory for each complete run. `ci-result.json` records
the revision, toolchain, step timings and SHA-256 of the tested source files; it
stays incomplete after any failure or source change during the run. The
`Bedrock.xcresult` bundle contains screenshots, requests and UI diagnostics.

During development, the individual suites can be run separately.

Local core:

```sh
python3 scripts/validate-local-core.py --output .build/validation/core
```

Native Markdown, cross-paragraph selection, clipboard, and attachment regressions:

```sh
python3 scripts/validate-markdown-rendering.py \
  --markdown-package /path/to/resolved/swift-markdownkit \
  --output .build/validation/rendering
```

The two scripts accept `--developer-dir` and `--xcode` for an explicit toolchain. They require executed XCTest cases and fail if no test bundle/results are found.

Full app integration and native UI tests:

```sh
xcodebuild test \
  -project "Bedrock.xcodeproj" \
  -scheme Bedrock \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath .build/xcode-tests \
  -resultBundlePath .build/Bedrock.xcresult \
  -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO \
  ENABLE_TESTABILITY=YES \
  SWIFT_OPTIMIZATION_LEVEL=-O \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) WORKBENCH_TESTING' \
  BEDROCK_APP_BUNDLE_IDENTIFIER=AWS.Amazon-Bedrock-Client-for-Mac.UITestHost \
  BEDROCK_TEST_PYTHON="$(python3 -c 'import sys; print(sys.executable)')" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=
```

App and test executables use local ad-hoc signing for validation; no Apple
account or distribution certificate is needed. Leaving the UI runner unsigned
can make macOS reject the copied runner template as damaged.
Create `/private/tmp/bedrock-ui-fixtures` before running this standalone command.
The complete CI entry point creates it and checks normal macOS UI automation
readiness. If Xcode requires user authentication, finish that authentication
before rerunning the required UI suite; a skipped UI run is not complete CI.

The scheme supplies an isolated data directory and test-only offline mode.
Fixture paths resolve from the test sources, or from `BEDROCK_TEST_FIXTURES`.
UI tests create fresh storage for each case. Tests cover real local MCP
subprocesses; optional public MCP diagnostics require `BEDROCK_LIVE_NETWORK_TESTS=1`.

The validation workflow runs on every push to `main`, on pull requests, and on demand. Release branches use pull-request validation instead of also starting a duplicate push run. It retains logs, screenshots, actual loopback request payloads, timing results and an `.xcresult`. Renderer and clipboard cases run once in the optimized app suite; CI verifies that every case declared in those source files passed. The standalone harness remains available for focused local work.

Pinned package sources and optimized build intermediates are cached by toolchain and dependency graph. CI compiles for the runner's architecture and disables editor indexing; distribution builds still include both architectures. Release reuses the successful main run for the exact tag commit after matching its source hashes, executable permissions, and complete Xcode inventory. It builds and checks the distribution separately. Stage timings appear in the workflow summary, and long stages report progress every 30 seconds. See [CI coverage](testing.md) for the scenario map and the distinction between deterministic and live AWS checks.

## Performance checks

Use an optimized **Release** executable for timing. Stop compilation before recording results, preserve existing data, and identify synthetic fixtures separately from model responses.

After building, quit any running preview and pass the exact newly built app:

```sh
scripts/run-preview.sh \
  ".build/xcode/Build/Products/Release/Amazon Bedrock.app"
```

The script preserves preview data, rejects replacement of a running executable
(including `/tmp`/`/private/tmp` aliases), and stages a fresh app bundle so deleted
resources cannot survive an update. The staged executable is compared with the
selected build before signing; the previous app is retained in `previous-builds`.
It writes `preview-build.json` with the source and installed app versions and
executable hashes. Ad-hoc signing changes the installed hash. The script requires
an explicit build and never falls back to an older Debug app.
This launcher uses actual AWS connections and rejects the CI `UITestHost` app
and offline-test environment. Build the normal Release app in a separate
Derived Data directory; omit `WORKBENCH_TESTING` and the test bundle override.
Do not clear all Swift compilation conditions, because dependency packages
have their own required platform flags.
For a separate documentation capture, set both
`BEDROCK_PREVIEW_ROOT` and `BEDROCK_PREVIEW_BUNDLE_IDENTIFIER` to new values so
neither preferences nor conversations are shared with another preview.

For manual interaction with deterministic responses, use the separate test
launcher after the CI test app has been built:

```sh
python3 scripts/run-ui-fixture.py \
  ".build/ci-derived/Build/Products/Release/Amazon Bedrock.app" \
  --output /tmp/bedrock-ui-review
```

It requires a new evidence directory and opens **Bedrock UI Tests**. It launches
the loopback server, uses synthetic credentials and fresh local data, records
actual SDK requests, and stops the fixture when the test app exits. It never
replaces the normal **Bedrock Validation** app. Reopening the test copy without
its fixture remains offline.

Include:

- Cold and warm opening of a long conversation.
- Continuous full-history scrolling, Find to an old message, returning to its reading position, and resizing.
- Long multilingual text and browser HTML paste; cancellation and exact ending.
- Multiple large images; repeated preview/zoom/copy/save/close.
- Streaming while reading history and queueing the next message.
- Main/Settings open, close, appearance changes, and restart.

Record wall-clock observations, process CPU/RSS, fixture size, macOS/toolchain, and build configuration. Accessibility automation includes input/snapshot overhead and is not a frame-time or render-TTI benchmark. UI checks and network latency should not be presented as renderer performance.

For repeatable input and scroll checks, compile the lightweight probe:

```sh
swiftc -O scripts/measure-ui-responsiveness.swift -o /tmp/bedrock-ui-probe
/tmp/bedrock-ui-probe PID scroll SCREEN_X SCREEN_Y > scroll.json
/tmp/bedrock-ui-probe PID typing COMPOSER_X COMPOSER_Y > typing.json
```

Open an isolated synthetic conversation and bring the app to the foreground first. Use the same fixture, window dimensions, appearance, and display for both builds. Typing requires an empty composer; the probe restores its own text and never sends a prompt. Scroll injects 360 events over six seconds while checking a single window attribute. Avoid full accessibility-tree snapshots during timing: they can be more expensive than the interaction being measured. Keep raw samples and report median, p95, maximum, failures, and total elapsed time.

See the [CI scenario map](testing.md) for regression coverage. Keep raw local measurements in the ignored `artifacts/` directory. When sharing results, include the tested revision, workload and limitations, and remove personal paths, account identifiers and conversation content.

## Storage and migration

Use a separate bundle identifier and `BEDROCK_WORKBENCH_DATA_DIR` when launching a development copy against isolated data. Never point tests at a user's production data folder.

Preserve history IDs, attachment references, drafts, queued work, skills, and explicit preferences. Retain the original data when migrating or importing, reject corrupt/unsupported input, and test a restart after any persistence change.

`BEDROCK_TEST_OFFLINE=1` only takes effect in Debug or a build explicitly compiled with `WORKBENCH_TESTING`, and requires an isolated data directory. UI tests can also set `BEDROCK_TEST_RUNTIME_PORT` to exercise Converse against the loopback protocol fixture. Only the exact `http://127.0.0.1:<port>` endpoint is allowed in that mode; other inference routes stay blocked. Distribution Release builds do not enable this test mode.

## Release

Keep `MARKETING_VERSION` equal in both app configurations, write `docs/releases/<version>.md`, verify the affected local regressions, and run:

```sh
python3 scripts/verify-release.py --tag v2.0.1
```

After main validation succeeds, push the matching version tag. GitHub verifies the complete main CI receipt for that exact commit, then builds an optimized universal app, verifies the production identity and both architectures, signs with Developer ID, notarizes and staples the app and DMG, and publishes the DMG and checksum. It does not repeat the full test suite. Missing, expired, incomplete, mismatched or failed CI evidence stops the release. Invalid notarization results also stop publication. Signing credentials come from repository secrets and are not used in pull-request validation.

To retry an existing immutable tag using updated release automation, dispatch **Build and Release** from `main` with `release_tag` set to that version. The workflow checks out and builds the tag's commit, pins Xcode to its successful main run, and checks that the remote tag still points to the same commit before publication.
