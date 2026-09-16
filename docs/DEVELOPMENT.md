# Development and validation

The Xcode project is the application entry point. The root Swift package exposes the platform-independent local core for fast regression tests; it is not a second application.

## Source layout

| Directory | Responsibility |
| --- | --- |
| `Sources/Bedrock/Core` | App lifecycle, scenes, commands, Core Data |
| `Sources/Bedrock/LocalCore` | Codable state, migration, routing, skills, tools, queues |
| `Sources/Bedrock/Managers` | AWS/MCP clients, persistence, orchestration, media |
| `Sources/Bedrock/Models` | Conversation and inference state |
| `Sources/Bedrock/Views` | Native UI, Markdown, search, previews, settings |
| `Sources/Bedrock/Utils` | Native editor, clipboard, search, shared utilities |
| `Sources/Bedrock/Resources` | Bundled offline resources and dependency notices |
| `Configuration` | Existing app identity, Info.plist, entitlements |

After adding or moving a Swift file, register it and validate project membership:

```sh
python3 scripts/register-workbench-sources.py
python3 scripts/validate-project-layout.py
```

The validator checks missing/duplicate files, app/test membership, resources, configuration paths, and the production bundle identifier. Moving source directories must not change the app's identity or existing user-data locations.

## Regression suites

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
  -project "Amazon Bedrock Client for Mac.xcodeproj" \
  -scheme "Amazon Bedrock Client for Mac" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath .build/xcode-tests \
  -resultBundlePath .build/Workbench.xcresult \
  -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO \
  ENABLE_TESTABILITY=YES \
  SWIFT_OPTIMIZATION_LEVEL=-O \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) WORKBENCH_TESTING' \
  BEDROCK_APP_BUNDLE_IDENTIFIER=AWS.Amazon-Bedrock-Client-for-Mac.UITestHost \
  CODE_SIGNING_ALLOWED=NO
```

The scheme supplies an isolated data directory, fixture location, and test-only offline mode. UI tests create fresh storage for each case. Tests cover real local MCP subprocesses; optional public MCP diagnostics require `BEDROCK_LIVE_NETWORK_TESTS=1`.

The validation workflow runs on every push to `main` and `release/**`, on pull requests, and on demand. It retains logs, screenshots, actual loopback request payloads, timing results and an `.xcresult`. The release workflow must pass the same suite before building and notarizing the distribution. See [CI coverage](CI_COVERAGE.md) for the scenario map and the distinction between deterministic and live AWS checks.

## Performance checks

Use an optimized **Release** executable for timing. Stop compilation before recording results, preserve existing data, and identify synthetic fixtures separately from model responses.

After building, quit any running preview and pass the exact newly built app:

```sh
scripts/run-workbench-preview.sh \
  ".build/xcode/Build/Products/Release/Amazon Bedrock.app"
```

The script preserves preview data, rejects replacement of a running executable
(including `/tmp`/`/private/tmp` aliases), and stages a fresh app bundle so deleted
resources cannot survive an update. The staged executable is compared with the
selected build before signing; the previous app is retained in `previous-builds`.
It writes `preview-build.json` with the source and installed app versions and
executable hashes. Ad-hoc signing changes the installed hash. The script requires
an explicit build and never falls back to an older Debug app.
For a separate documentation capture, set both
`BEDROCK_PREVIEW_ROOT` and `BEDROCK_PREVIEW_BUNDLE_IDENTIFIER` to new values so
neither preferences nor conversations are shared with another preview.

Include:

- Cold and warm opening of a long conversation.
- Earlier/newer paging, Find to an old message, scrolling, and resizing.
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

The complete scenario list is in [PERFORMANCE_VALIDATION_MATRIX.md](PERFORMANCE_VALIDATION_MATRIX.md); executed results and limitations belong in [PILOT_VALIDATION.md](PILOT_VALIDATION.md).

## Storage and migration

Use a separate bundle identifier and `BEDROCK_WORKBENCH_DATA_DIR` when launching a development copy against isolated data. Never point tests at a user's production data folder.

Preserve history IDs, attachment references, drafts, queued work, skills, and explicit preferences. Retain the original data when migrating or importing, reject corrupt/unsupported input, and test a restart after any persistence change.

`BEDROCK_TEST_OFFLINE=1` only takes effect in Debug or a build explicitly compiled with `WORKBENCH_TESTING`, and requires an isolated data directory. UI tests can also set `BEDROCK_TEST_RUNTIME_PORT` to exercise Converse against the loopback protocol fixture. Only the exact `http://127.0.0.1:<port>` endpoint is allowed in that mode; other inference routes stay blocked. Distribution Release builds do not enable this test mode.

## Release

Keep `MARKETING_VERSION` equal in both app configurations, write `docs/releases/<version>.md`, and run:

```sh
python3 scripts/verify-release.py --tag v2.0.0
```

After main validation succeeds, push the matching version tag. GitHub validates again, builds an optimized universal app, verifies the production identity and both architectures, signs with Developer ID, notarizes and staples the app and DMG, then publishes the DMG and checksum. Invalid notarization results stop publication. Signing credentials come from repository secrets and are not used in pull-request validation.
