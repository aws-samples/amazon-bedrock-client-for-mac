# Completion audit

Audited September 17, 2026. The [requirements ledger](requirements.md) is the
authoritative list. [Foxl parity](foxl-parity.md), [settings mapping](foxl-settings.md)
and the [original port checklist](port-checklist.md) provide supporting detail.
They overlap and must not be added together as a unique feature count.

This retains the original audit and its historical failures. Version 2.0.0 was
subsequently published from `c64956b` after main CI `35211853618` and release
workflow `35214571810` passed. Its signed universal DMG and update installation
were also verified. Version 2.0.1 addresses the independently reported streaming
overlap/flicker and image failures; its separate gate is tracked in
[requirements.md](requirements.md). An implemented code path, a type-check or a
screenshot does not close a behavioral requirement.

## Executed evidence

- The native transcript replacement passes targeted optimized-app checks in
  Light and Dark: a controlled response completes while the earlier passage
  stays at exactly the same screen position, typing remains responsive, and
  the latest-response action works. Full-history thumb scrolling, middle-message
  search, three Activity → Back returns, sidebar reflow, and ⌘N/⌘D draft behavior
  also pass. Three 4K-image preview cycles, original tool Input/Output inspection,
  and selected-text retention through stream completion pass in the same final
  executable. Nineteen native controller/container tests execute and pass,
  including 10,000-message access without creating every row. These required
  suites are now checked explicitly by CI. The final main workflow must still
  confirm this candidate before V01 and the delivery gates close.
  [Performance](../performance.md) records the executable hash, measurements,
  captures and limits of the local evidence.
- Main CI `35193102534` completed with 138 passing cases, four optional live
  checks skipped, and one failure:
  `testFinishingAStreamDoesNotMoveThePassageBeingRead`. That Release app
  reproduced an unresponsive main thread in SwiftUI/AttributeGraph after
  scrolling or finishing the stream. This was an application failure, separate
  from the earlier fixture-consent and local IDE-session problems. All five
  updater cases pass in that hosted run. The stream failure keeps V01 and the
  delivery gates open; passing a build or an intermittent local repetition
  does not close it. Light/Dark completion and native selection regressions
  have been added for the subsequent verification.
- Hosted `35190013784` reached the new small-screen layout and exposed a
  download-fixture startup problem. Python's default HTTP server performed a
  reverse hostname lookup and opened a macOS network-consent dialog; the
  recordings show that dialog covering the skills/tool controls and transcript.
  The fixture now binds literal loopback without name discovery, publishes its
  port atomically and retains startup errors. Its no-discovery regression passes.
  All five updater XCTest cases then pass in an optimized standalone bundle
  compiled from the identical app/test sources, including the three failed
  download cases. This targeted execution avoids the local IDE-session blocker.
  The richer stream fixture reads the preceding completed turn before checking
  that finishing a response preserves its position.
- Cold searches in the normal 1,000-message conversation exposed premature
  completion: the projected row was centered while its actual native view was
  still 1,065 points away. Completion now requires both native and measured
  visibility. The optimized app reaches three previously offscreen results
  in 0.63–0.72 seconds and retains the reading position within 0.2 points on
  three Activity → Back returns. Six direct AppKit checks pass against the
  actual controller source, including delayed placement and user cancellation.
  Native XCTest coverage was added and the hosted long-history fixture now
  includes tables, nested lists and code.
- Hosted `35186121048` exposed an initial-window sizing problem on its
  1,024 × 768 display. The new main-display assertion caught a 1,120-point
  window extending beyond the screen; the recording confirms clipped sidebar
  content. Fresh-window sizing now uses the display's available width and
  reserves titlebar height. Existing saved window geometry remains unchanged.
- Automatic-update review found a changed DMG volume name, temporary-download
  lifetime risk, volume guessing and deletion of the old app before copying.
  The release volume name is restored for 1.x compatibility. The new updater
  retains the existing preference, checks the official release/asset, verifies
  the download and signing identity, stages on the target volume and waits for
  graceful quit. Disposable signed-bundle tests cover successful replacement,
  quit timeout, altered code and restoration after a failed second rename.
  Native loopback tests cover actual download bytes/lifetime and rejected
  HTTP, size, digest, identity and signature failures. Two test-fixture mistakes
  (the `chflags` executable path and URL directory-bit equality) were corrected
  and only those failed cases were repeated. All eight core and four native
  update scenarios have passing local executions.
  Read-only signature checks against the installed 1.4.10 app accept its
  Developer ID and reject a different team. This caught and corrected the
  `codesign -R` requirement-source prefix. A positive native regression was
  added; its local build passed, but XCTest waited for its IDE session before
  executing either selected test, so that attempt was stopped and retained as
  runner evidence. The additional case subsequently passed in the targeted
  standalone bundle and remains part of the final hosted gate.
  A standalone optimized executable compiled from the actual installer and
  process-runner sources then passed all five signature checks, including the
  installed 1.4.10 identity and mismatched-version rejection. The normal Release
  app's General → Check now and its single Check for Updates menu item completed
  against GitHub, re-enabled the control, and preserved the disabled
  automatic-check preference.
- The current local XCTest UI runner timed out while enabling Automation Mode;
  this Mac requires user authentication for that mode. That attempt did not
  execute the three selected UI cases and is not counted as a pass. Normal
  Release app interaction and the full hosted main workflow remain the UI gates.
- The normal universal Release build passes identity, hardened-runtime and
  ad-hoc signature checks. Separate selected-Xcode architecture checks pass for
  arm64 and x86_64 and reject a missing Intel slice. That verified command form
  replaces the failing combined invocation in the release workflow.
- Local `833f9d3` passed all non-UI suites and 26/27 UI scenarios. Its remaining
  default-window-size assertion inherited saved geometry from the small-window
  scenario. The UI fixture now ignores that saved frame at launch and moves its
  own window onto the primary display for reliable captures on multi-monitor
  systems. It still tests the app's real default size and does not change
  production window restoration. Small-window history, initial titlebar/default
  size and long-attachment relaunch then each passed three consecutive runs.
- Actual small-window inspection isolated a wheel-input trap in short native
  tool previews. Scrolling outside the preview worked; scrolling inside it
  could leave Open details out of reach. Fitting inline previews now pass wheel
  input to the conversation. Long outputs and standalone details retain their
  own scrolling. The expanded-tool model-switch, small-window full-history and
  skills/shell original-details UI scenarios each passed three times. All 15
  native viewport cases also passed three times after correcting an assertion
  that ran before AppKit applied its wheel animation.
- Hosted `35180323291` showed the first conversation message briefly appearing
  and then jumping to question 32 during late layout at the end of a thumb
  drag. The earlier drag-endpoint adjustment was insufficient. Explicit
  top-boundary preservation and observation of late native clip adjustments
  now address that path. The local `4f50cee` suite was canceled to incorporate
  this correction; its partial passing result is not a complete CI receipt.
  Subsequent testing caught a 40-point titlebar-inset shift during tool
  inspection. The boundary now comes from AppKit's constrained clip bounds,
  with a separate inset regression, rather than a hardcoded zero offset.
- Complete CI at `9fc1597` passed all non-UI checks and 26/27 UI scenarios.
  The remaining tool-details click failure was reproduced in the recording:
  automatic following moved the expanded card just before the click. Explicit
  tool/reasoning inspection now preserves the current reading position and
  cancels queued following. The UI regression retains a single details click
  and additionally checks that the disclosure header remains in place.
  Both this scenario and the expanded-tool model-switch scenario subsequently
  passed three consecutive runs in `tool-inspection-position.xcresult`.
- Complete local CI passed on clean revision `765e40e`: core 115/115,
  renderer/clipboard 43/43, native app 101 passed plus four optional network
  skips, and UI 26/26. The receipt verifies unchanged source hashes and
  executable permissions. Renderer cases overlap the app suite.
- A follow-up removes unchanged system-prompt writes during Models rendering
  and the duplicate default-model assignment. Its six native lifecycle/preset
  tests and the Settings UI scenario pass without the reproduced SwiftUI
  publishing warning. The final whole-suite gate must include this follow-up.
- Hosted CI `35176696548` passed all non-UI suites and 25/26 UI cases. On its
  smaller display, the full-history thumb drag stopped below the first prompt.
  Its endpoint now clears the top of the native scroll slot; the first-message
  visibility assertion is retained.
- Real online testing found a separate SwiftUI layout hang when models were
  rapidly changed after inspecting an expanded tool. The corrected normal
  Release build completed 12 changes, actual image generation, three
  zoom/Fit/close cycles, and an Astra follow-up. A new UI regression keeps the
  tool expanded and an unsent draft intact across chat/image model changes.
  That scenario and full-history scroll/search/return each passed three
  consecutive runs. Native, leading-aligned inline tool previews were added
  afterward and remain part of the final whole-suite gate.
- Full local CI at `92dd023` passed all non-UI cases and 26/27 UI scenarios. The
  remaining failure was a new test expecting compact empty JSON from a pretty
  printer. The corrected check verifies parsed input, exact preview/detail
  agreement, original output and leading alignment; its actual UI run passes.
  This targeted result does not replace a complete CI receipt.
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
| Continuous history | The native container passes scrolling/search/navigation, width reflow and Light/Dark stream-completion checks locally. Confirm the final implementation in the complete main workflow. |
| Tool details and model switching | Actual Input/Output inspection passes. A subsequent rapid model-switch layout hang was reproduced and corrected; include its new expanded-tool/draft scenario in the complete local and hosted suites. |
| Quick Access | Actual Escape/refocus/submission passes after correcting panel/main-window handoff and avoiding redundant window-style changes. |
| Rich selection | Actual rich HTML and original Markdown copy passes with the corrected assistant-role fixture. |
| Automation models | Shared picker deduplicates model families, exposes provider/route, and preserves the exact route through save/relaunch/edit. Actual UI case passes. |
| Complete local suite | `full-ci-765e40e` is the earlier complete receipt. Later changes use targeted local checks under the latest instruction; the final main workflow provides the complete current receipt. |

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
helpers have been removed. Actual transcript, attachment and image-preview
regressions passed in the complete local suite; the final hosted run must
include the subsequent corrections.

Local and hosted validation share `python3 scripts/ci.py`. The latest instruction
replaces mandatory repeated full local runs with targeted checks of changed or
failing paths. Those regressions have passed; the redundant `9327147` local rerun
was canceled as requested and is not reported as a passing complete receipt.
The later main run exposed a stream-completion hang; the native transcript
replacement and its targeted verification are described above. The final main
revision must pass the complete GitHub pipeline, followed by
universal signing, notarization, DMG verification and published-asset checks.
No release has been triggered by this audit.

## Later CI performance work

- [ ] Measure time spent resolving dependencies, compiling and running each
  suite. Investigate cache reuse, independent job parallelism and using the
  verified main commit's artifacts during release without weakening source,
  signing or test verification. This is deferred until after v2.0.1; do not
  repeat full local CI when the changed-path checks have already passed.

## v2.0.1: one Archive

The latest request combines Archive and Trash as one behavior, beyond the earlier
shared Settings surface. Existing hidden conversations must migrate into Archive.
Restore, restore-and-open, search and confirmed permanent delete remain available
there; `⌘D` retains its navigation and draft behavior. The dedicated A01–A06
checks in [requirements.md](requirements.md) track this work. The user subsequently
authorized including it in v2.0.1 if CI had not already consumed 20 minutes.
The previous candidate was still queued after about 12 minutes with no executed
steps, so its run was canceled and the changes combined. Migration, byte-preserving
recovery, paused queues and the Archive UI passed targeted local checks. The
combined revision still needs complete main CI and release validation.
