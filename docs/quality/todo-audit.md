# Completion audit

Audited September 16, 2026. The [requirements ledger](requirements.md) is the
authoritative list. [Foxl parity](foxl-parity.md), [settings mapping](foxl-settings.md)
and the [original port checklist](port-checklist.md) provide supporting detail.
They overlap and must not be added together as a unique feature count.

The rebuild is **not yet fully validated or released**. An implemented code path,
a type-check or a screenshot does not close a behavioral requirement.

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
- Local UI execution remains blocked before the first scenario: the correctly
  ad-hoc-signed runner times out enabling macOS Automation Mode. The system
  reports that user authentication is required. This is **not a passing local
  CI run**; the full suite must execute again after normal Xcode authentication.
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

## Failure follow-up

| Area | Required follow-up |
| --- | --- |
| MCP fixture connections | The isolated-manager override now passes locally, including cancellation, reconnect, timeout and output tests. Hosted re-execution remains required. |
| Global search | Verify the actual centered panel, outside click, Escape and retained draft. |
| Stream reading position | Fix the file-panel interruption, then execute the stream completion/scroll-anchor assertions. |
| Error recovery | Preserve the service's actionable message and prove a following request succeeds. |
| Image preview | Verify Fit after animated zoom, original image copy, repeated close/reopen and app responsiveness. |
| Quick Access | Exercise the real panel, editor, Escape and main-conversation handoff. |
| Skill removal | Verify the corrected hit area through an actual click, including small displays. |
| Initial size | Respect the available display width while preserving the usable sidebar and minimum content size. |

## Implementation gaps that remain open

The following are real Foxl convenience gaps, rather than missing checkmarks:

- Explicit summary-based context compaction.
- Agent tools for local image inspection, conversation search and automations.
- Custom shell/HTTP tools with safe configuration import/export.
- Weekday/active-hour automation schedules with timezone and next-run preview.
- Separate notification outcomes and supported shortcut customization.
- Configurable model fallback and per-turn budgets distinct from output limits.

Each has an individual item in [Foxl parity](foxl-parity.md). Existing but
unverified features—settings controls, automation editing, Activity filtering,
history management and demo routes—remain open until exercised.

Output-limit continuation now records the actual Converse stop reason and
preserves an unrelated composer draft. Background start/poll/stop is implemented
with bounded output, per-chat ownership, process-group termination and shutdown.
Their dedicated UI tool-loop cases are still awaiting execution, so FC23/FT04
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
