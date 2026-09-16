# CI regression coverage

`Workbench validation` runs for every main push, release branch push, pull request and manual dispatch. Release tags call the same workflow before signing or publication. The app runs with **Release optimization** and isolated local data; a distinct bundle identity protects existing user preferences.

## Tests and scenarios

| Regression | Automated coverage |
| --- | --- |
| First keystroke invalidates the whole scene | `WindowLifecycleTests.testTypingOnlyInvalidatesTheAffectedDraftIndicator`; long-conversation typing metric |
| Long history, bounded paging, scroll and navigation | `NavigationPerformanceTests`, `ConversationViewportTests`; 1,000-message UI fixture, paging anchor preservation and Activity → Back |
| Command-N, D, B, F, K and Settings | UI shortcut, centered search, titlebar and Settings lifecycle cases |
| Quick Access escape and handoff | UI opens the real panel, dismisses it, submits through the composer and verifies the main conversation and SDK request |
| Streaming and durable queues | UI verifies sequential requests, keeps an unsent draft, stops a partial response, restarts, checks no automatic replay and resumes |
| Queue editing, outbox corruption and recovery | `ConversationConvenienceTests`, `AttachmentDraftTests`; on-disk snapshots and exact attachment identity |
| In-chat model switch | UI sends through Nova, selects GPT-6 Astra, then verifies the new request model and retained context |
| Local skills and shell | UI exercises three real tool cycles: list skills, read `code-review`, run harmless `printf`; asserts the actual output and exit status |
| Tool disclosure and original details | UI expands the named tool, verifies separate actions, opens the exact original output and input |
| MCP lifecycle and mixed content | Real Python stdio servers: duplicate tool names, nested arguments, stderr pressure, cancellation, timeout, reconnect, media and resources |
| Source file clipboard regression | UI pastes a `.swift` file URL, retains its draft, sends through the real SDK and checks exact UTF-8 bytes; native test covers multiple source types |
| Long text, HTML and mixed images | Native clipboard tests preserve Unicode, plain text priority, sanitized HTML, image ordering, import cancellation and bounded decoding |
| Welcome/chat attachment restart | UI gracefully quits and reopens with the full long-text attachment intact; native tests cover image/document draft identity |
| Markdown and copy | Native renderer tests cover mixed blocks, lists, tables, code, full-message selection, marker exclusion, context menus and original Markdown copy |
| Generated image crash | UI repeatedly opens a 4K image, zooms, fits, copies exact PNG bytes, closes and reopens; native tests cover decoding and preview lifecycle |
| Light / Dark / System and settings | UI opens all nine settings panes, captures screenshots, selects all appearances and repeatedly closes/reopens Settings |
| Error recovery | UI receives a real SDK validation error from the fixture and successfully sends the next message |
| Existing data and explicit settings | Core tests cover historical JSON/Core Data-compatible records, migration defaults, future/corrupt data, import/export, paths and atomic writes |
| Model/task compatibility | Core routing and demo tests; app inference configuration tests for omission, reasoning, profile and model-family behavior |
| Release integrity | Source/tag/version match, production bundle identity, Intel + Apple silicon executable, strict signature, hardened runtime, accepted notarization and stapled app/DMG |

## What the loopback server tests

`Tests/Fixtures/bedrock_runtime.py` serves AWS Converse JSON and binary event-stream responses over HTTP. Tests run the app's actual AWS SDK, request serialization, stream decoder, tool loop, queue, persistence and rendering. Fixture tests validate frame sizes, headers and both CRCs first. No AWS credential or paid request is needed.

Only fixed synthetic prompts and attachments are recorded. SDK request logs are attached to the test result so an incorrect model, missing tool schema, lost context or changed document bytes is visible.

## Performance evidence

CI records clock metrics for a real, bounded 1,000-message conversation and asserts reading-position preservation, retained text, working commands and continued app responsiveness. Native viewport and draft-observation tests catch the structural regressions that caused the earlier hangs.

Dedicated hardware measurements use `scripts/measure-ui-responsiveness.swift`; the workload, raw measurement interpretation and results are described in [PERFORMANCE.md](PERFORMANCE.md). Accessibility round trips include automation overhead and are not display frame times. Hosted CI load and display settings differ from a user's Mac.

## Live checks

Deterministic tests do not prove account-specific model access, all regions, a provider's generated content, microphone permissions or external MCP credentials. Those require live checks against the intended account and hardware. The recorded local runs and their limits are in [PILOT_VALIDATION.md](PILOT_VALIDATION.md). Optional public MCP diagnostics remain opt-in with `BEDROCK_LIVE_NETWORK_TESTS=1`.

Validation artifacts contain `summary.json`, logs and `Workbench.xcresult`, including screenshots and UI measurements. A failed test blocks the release job; adding a test or compiling it is not recorded as a passing execution.
