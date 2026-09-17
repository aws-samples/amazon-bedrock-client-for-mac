# Completion audit

Audited September 17, 2026. The [requirements ledger](requirements.md) is the
authoritative list. [Foxl parity](foxl-parity.md), [settings mapping](foxl-settings.md)
and the [original port checklist](port-checklist.md) provide supporting detail.
They overlap and must not be added together as a unique feature count.

This is the pre-release audit. GitHub Actions receipts and Releases record the
subsequent release execution. An implemented code path, a type-check or a
screenshot does not close a behavioral requirement.

## Executed evidence

- Local optimized-app integration previously executed 73 cases: 69 passed and
  four optional public-network cases were skipped. That result predates the
  repository reorganization and must be repeated.
- Hosted run `35105311938`, revision `9325e08`, built the optimized app and
  executed 94 native/UI cases: 76 passed, 14 failed and four optional network
  diagnostics were skipped. The UI subset passed 14 of 21 cases.
- The same run passed the 88-case portable core suite and the separate native
  renderer/clipboard suite. Some renderer cases also run in app integration;
  they are not additional unique coverage.
- The reorganized source built locally with Xcode 27, Release `-O`. Its native
  app suite executed 77 cases: 73 passed and the four opt-in public MCP cases
  skipped. All seven local MCP lifecycle cases and four new configuration
  security cases passed. Core (88), standalone renderer/clipboard (37), and
  loopback protocol (3) checks also passed.
- An earlier local runner could not enable macOS Automation Mode. That historical
  setup failure is no longer the current blocker: the authorized local XCTest
  session now runs actual app interactions. The readiness report records the
  automation state without mistaking that flag for a completed UI test.
- The attachment/background-process changes passed 95 portable core cases and
  78 optimized native cases locally (74 passed, four optional network skips).
  Bulk export checks original bytes, duplicate names, existing-file preservation,
  invalid images and temporary-file cleanup. These results do not cover the UI
  suite, and the subsequent fixture-signing changes still need re-execution.
- Hosted run `35111372487` exposed a separate signed-runner setup problem:
  `/usr/bin/python3` delegates to `xcrun`, which refuses the runner's sandbox,
  and the runner's default temporary directory is inside its private container.
  The fixture now receives the actual Python executable and uses a disposable,
  explicitly entitled shared test directory. Loopback-server entitlement is
  limited to the test target. The app's entitlements are unchanged.
- Actual typing/scroll measurements and their workload limits are retained in
  [Performance](../performance.md). These short observations do not establish
  a long-session memory plateau or prove every conversation size.
- Actual Light/Dark screenshots and the demonstration are described in
  [Media](../media.md), including their source revision.
- The current core validation wrapper passed 115 cases. New optimized native
  tests passed for exact file-line ranges, actual image bytes and configured
  restrictions, and automation create/update/persistence. Eleven viewport cases
  cover layout, lazy-row restoration, teardown and cancellation.
- Targeted optimized UI runs passed automation model grouping/provider identity
  and save/relaunch/edit with an unchanged route; real skills/shell tool loops
  and original tool details; Quick Access escape/refocus/submission; rendered
  HTML selection versus source-Markdown copy; model-switch context; long-history
  typing/shortcuts; and stream completion without moving the reading position.
- Repeat testing after the first scroll-start correction exposed another failure:
  SwiftUI's corrected row position differed from its stale native view by 1,104
  points. The viewport now uses actual content-layout coordinates and preserves
  the pending target while its native view is temporarily detached.
- `authoritative-layout-restoration.xcresult` passed all 11 viewport cases three
  times. Both the 1,000-message full-scroll/search/return scenario and completion
  of a controlled stream while reading an earlier passage passed three times.
  The thumb reaches the first message in one drag. User scrolling cancels
  restoration at the native scroll-start notification. The run used AWS SDK
  1.7.85/Smithy 0.252.0 without the temporary diagnostic logging.
- A separate real interaction restored question 250 to exactly the same screen
  coordinate on three Activity → Back round trips. Three 61-character typing
  passes measured 8.66–8.96 ms median and 13.27–15.98 ms p95, with zero failures;
  all three scheduled six-second scroll probes completed. See the methodology
  and executable identity in [Performance](../performance.md).

## Failure follow-up

| Area | Required follow-up |
| --- | --- |
| MCP fixture connections | The isolated-manager override now passes locally, including cancellation, reconnect, timeout and output tests. Hosted re-execution remains required. |
| Continuous history | Actual scrolling/search/navigation and stream-completion scenarios each passed three consecutive runs after the measured-coordinate correction. Include them in the complete local and hosted suites. |
| Tool details | The disclosure is now one distinct button instead of competing tap/disclosure handlers. Actual Input/Output inspection passes. |
| Quick Access | Actual Escape/refocus/submission passes after correcting panel/main-window handoff and avoiding redundant window-style changes. |
| Rich selection | Actual rich HTML and original Markdown copy passes with the corrected assistant-role fixture. |
| Automation models | Shared picker deduplicates model families, exposes provider/route, and preserves the exact route through save/relaunch/edit. Actual UI case passes. |
| Remaining suite | Global search dismissal, error recovery, image preview, skill removal, initial size, queues and attachments still require the final complete-suite execution against unchanged source. |

## Implementation gaps that remain open

The following are real Foxl convenience gaps, rather than missing checkmarks:

- Explicit summary-based context compaction.
- Custom shell/HTTP tools with safe configuration import/export.
- Separate notification outcomes and supported shortcut customization.
- Configurable model fallback and per-turn budgets distinct from output limits.
- Eligible read-tool caching with invalidation after writes.
- Activity aggregation/retry, localization and an issue-report action.

Each has an individual item in [Foxl parity](foxl-parity.md). Existing but
unverified features—settings controls, automation editing, Activity filtering,
history management and demo routes—remain open until exercised.

Local image inspection, conversation search and automation tools are implemented.
`complete-drag-and-tool-feedback.xcresult` passed their actual SDK loop: a 64×48
image reached the next model request, a marker from an earlier conversation was
found, and a paused automation appeared in the app with its timezone and weekdays
retained. Native/core cases separately verify restrictions and update persistence.
Weekday/active-hour schedules, timezone selection and next-run preview are also
implemented, including DST and overnight-window tests. Unverified UI combinations
remain open.

## Current repository and release gates

The source layout uses `App`, `Core`, `Services`, `Features`,
`UI` and `Resources`. Test targets match their directories. The app bundle
identifier, persisted keys, attachment references, Core Data schema and on-disk
history locations are compatibility requirements even when Swift type and file
names change.

The message presentation code is now split into transcript attachments,
disclosures, Markdown, images and video. Unused synchronous image conversion
helpers have been removed. This split compiled with the optimized native suite;
it still needs actual transcript, attachment and image-preview UI regression.

Local and hosted validation use one entry point, `python3 scripts/ci.py`.
Before a release, a complete local run must pass against unchanged source and
record its hashes in `ci-result.json`. The final main revision must then pass
on GitHub, followed by universal signing, notarization, DMG verification and
published-asset checks. No release has been triggered by this audit.
