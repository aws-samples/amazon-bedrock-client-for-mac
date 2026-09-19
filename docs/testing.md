# CI regression coverage

`CI` runs for every main push, pull request and manual dispatch.
Local validation and GitHub share `python3 scripts/ci.py`. For focused changes,
run the affected or previously failing suites locally. The final main revision
must pass the entire GitHub pipeline before release; targeted local results do
not replace that gate.
Release tags verify and reuse the complete successful main run for their exact
commit, including source hashes, executable modes and the Xcode case inventory.
The full suite is not repeated during release. The app runs
with **Release optimization** and isolated local data; a distinct bundle identity
protects existing user preferences.

The full pipeline executes renderer and clipboard cases once, inside the optimized
app suite, and compares the executed inventory with every test declared in their
source files. The standalone rendering harness remains available for focused local
checks. Release-branch pushes do not duplicate pull-request validation.

## Tests and scenarios

| Regression | Automated coverage |
| --- | --- |
| Assistant response overlaps or scrolls independently of neighboring messages | `NativeTranscriptTests` changes child state without republishing the message array and checks growth, shrinkage, reading position and bottom following. Light/Dark UI tests load long WebKit Markdown beside image/text attachments, assert non-overlapping frames, scroll over the actual response, resize the window, open an image, and reopen the conversation. A controlled stream crosses the native/WebKit threshold, finishes while scrolled upward, then switches models and sends another prompt. |
| Streaming flicker and cold long-response recreation | Native tests sample the first line during deferred height changes and alternate legacy scrollbar widths while keeping a 9,000-point response alive. A cold Markdown-wrapper test exercises the real native/WebKit handoff. WebKit tests preserve paragraph/list node identity and selection, bound appended-block opacity effects, and check Reduce Motion. |
| Long screenshots, panoramas, SVGs and old image history | Native tests decode 42,000-pixel screenshots and panoramas, a 108-megapixel source and self-contained SVGs off the main thread; reject external SVG resources; verify fitted pixels, aspect ratio, previews and original-byte preservation. UI resends an older image/document conversation and compares the actual SDK image dimensions and complete document bytes while retaining the stored original. |
| Collapsible sidebar and date groups | Core tests cover stable chronological ordering, Today/Yesterday, both daylight-saving transitions, time-zone changes, midnight identity and earlier preferences. Light/Dark UI tests operate Library navigation, pin a chat, collapse sections, relaunch, restore choices and open imported chats under their original dates. |
| First keystroke invalidates the whole scene | `WindowLifecycleTests.testTypingOnlyInvalidatesTheAffectedDraftIndicator`; long-conversation typing metric |
| Opening Models publishes unchanged preferences during rendering | `WindowLifecycleTests.testLoadingPromptPresetsPreservesInstructionsWithoutPublishingUnchangedSettings`; actual all-panes Settings interaction |
| Continuous long history, scroll and navigation | `NavigationPerformanceTests`, `ConversationViewportTests`; a complete 1,000-message UI fixture in a 1024×674 window, one scroll-thumb drag to the first message, search through the full history, Activity → Back, and finishing a controlled stream while reading an older passage. Native cases cover late clip-offset compensation and top-boundary intent without suppressing the next user gesture. |
| Command-N, D, B, F, K and Settings | UI shortcut, centered search, titlebar and Settings lifecycle cases |
| Quick Access escape and handoff | UI opens the real panel, dismisses it, submits through the composer and verifies the main conversation and SDK request |
| Streaming and durable queues | UI verifies sequential requests, keeps an unsent draft, stops a partial response, restarts, checks no automatic replay and resumes |
| Queue editing, outbox corruption and recovery | `ConversationConvenienceTests`, `AttachmentDraftTests`; on-disk snapshots and exact attachment identity |
| In-chat model switch | UI sends through Nova, selects GPT-6 Astra, then verifies the new request model and retained context |
| Model switch after inspecting tools | UI runs real local tools, opens their original Input/Output, leaves the disclosure expanded, and repeatedly switches between Astra and Stable Image Ultra while preserving an unsent draft |
| Local skills and shell | UI exercises three real tool cycles: list skills, read `code-review`, run harmless `printf`; asserts the actual output, exit status, stable disclosure position and one-click access to original output |
| Update discovery and installation | Core tests cover stable-version selection, the legacy DMG asset, untrusted URLs, literal paths, exact-process quit waiting, timeout preservation, altered signatures, successful replacement, and rollback after a failed second rename. Native tests download real loopback HTTP responses and check temporary-file lifetime, exact bytes, size/digest checks, error pages, and application identity/signature rejection. Developer ID signing and notarization are verified by the release workflow. |
| Image, conversation search and automation tools | UI verifies the actual image bytes in the next SDK request, finds a marker in an earlier saved conversation, creates a paused automation, and checks its persisted timezone/weekdays and visible card |
| Automation model identity | UI chooses a provider group and model through the shared picker, verifies deduplication and the inference route, then saves, relaunches and edits without changing that route |
| Background commands | Real-process core tests cover output offsets, bounded tails, per-chat ownership, capacity, polling cancellation and child-process termination; UI starts, polls and stops through the actual tool loop |
| Output-limit continuation | Core tests distinguish truncation from filtering/cancellation and decode older run records; UI continues the actual response while retaining an unrelated draft |
| Tool disclosure and original details | UI expands the named tool, verifies stable position and leading-aligned native previews with exact text, scrolls over a fitting preview to reach Open details, then opens the original output and input. Native cases verify that long output keeps its own scrolling. |
| MCP lifecycle and mixed content | Real Python stdio servers: duplicate tool names, nested arguments, stderr pressure, cancellation, timeout, reconnect, media and resources |
| Source file clipboard regression | UI pastes a `.swift` file URL, retains its draft, sends through the real SDK and checks exact UTF-8 bytes; native test covers multiple source types |
| Long text, HTML and mixed images | UI first pastes a PNG-only clipboard, then long text and two images, sends them, and checks exact text plus all three images in the SDK request. Native tests cover Paste-menu validation, Unicode, plain-text priority, sanitized HTML, ordering, cancellation and bounded decoding. |
| Welcome/chat attachment restart | UI gracefully quits and reopens with the full long-text attachment intact; native tests cover image/document draft identity |
| Markdown and copy | Native renderer tests cover mixed blocks, lists, tables, code, full-message selection, marker exclusion, context menus and original Markdown copy |
| Generated image crash | UI repeatedly opens a 4K image, zooms, fits, copies exact PNG bytes, closes and reopens; native tests cover decoding and preview lifecycle |
| Image bulk export | Native tests preserve original image bytes and dimensions, select the actual file format, retain existing files, assign unique names and report individual failures |
| Light / Dark / System and settings | UI opens all nine settings panes, captures screenshots, selects all appearances and repeatedly closes/reopens Settings |
| Error recovery | UI receives a real SDK validation error from the fixture and successfully sends the next message |
| Existing data and explicit settings | Core tests cover historical JSON/Core Data-compatible records, migration defaults, future/corrupt data, import/export, paths and atomic writes |
| Model/task compatibility | Core routing and demo tests; app inference configuration tests for unknown-model sampling defaults, saved overrides, reasoning, profile and model-family behavior. Kimi K3 UI cases exercise Runtime Responses with and without documents, real local tools, follow-ups, Thinking off, cache controls, and Light/Dark settings. |
| Release integrity | Source/tag/version match, production bundle identity, Intel + Apple silicon executable, strict signature, hardened runtime, accepted notarization and stapled app/DMG; read-only mounting verifies the packaged app, exact executable and Applications link |

## What the loopback server tests

`Tests/Fixtures/bedrock_runtime.py` serves AWS Converse JSON and binary event-stream responses over HTTP. Tests run the app's actual AWS SDK, request serialization, stream decoder, tool loop, queue, persistence and rendering. Fixture tests validate frame sizes, headers and both CRCs first. No AWS credential or paid request is needed.

UI launches ignore a previous test's saved MainWindow frame, preserving the app's
actual default-size behavior. On multi-monitor Macs, the fixture moves its window
to the primary display without resizing it so XCTest can capture the full window.
These launch overrides do not change the normal app's window restoration.

Only fixed synthetic prompts and attachments are recorded. SDK request logs are attached to the test result so an incorrect model, missing tool schema, lost context or changed document bytes is visible.

## Performance evidence

CI records clock metrics for a real, bounded 1,000-message conversation and asserts reading-position preservation, retained text, working commands and continued app responsiveness. Native viewport and draft-observation tests catch the structural regressions that caused the earlier hangs.

Dedicated hardware measurements use `scripts/measure-ui-responsiveness.swift`; the workload, raw measurement interpretation and results are described in [performance.md](performance.md). Accessibility round trips include automation overhead and are not display frame times. Hosted CI load and display settings differ from a user's Mac.

## Live checks

`scripts/validate-app-termination.py --output /tmp/bedrock-termination-check`
runs separate AppKit processes without XCTest injection. It verifies saving
before termination, repeated Quit requests, recovery after a failed save, and
the production installer replacing and reopening a signed disposable app.
This catches termination-loop deadlocks that an injected XCTest host can hide.
It does not modify an installed Bedrock app or its data. CI requires this stage
before issuing the release receipt.

Deterministic tests do not prove account-specific model access, all regions, a provider's generated content, microphone permissions or external MCP credentials. Those require live checks against the intended account and hardware. Keep local results in `artifacts/`; share only sanitized summaries that identify the tested revision and limitations. Optional public MCP diagnostics remain opt-in with `BEDROCK_LIVE_NETWORK_TESTS=1`.

Validation artifacts contain `ci-result.json`, `summary.json`, logs and
`Bedrock.xcresult`, including screenshots and UI measurements. A failed test
blocks the release job; adding a test or compiling it is not recorded as a
passing execution.

## Local UI test setup

The local command requires a signed-in graphical macOS session and full Xcode.
The runner is ad-hoc signed with **Sign to Run Locally**; it does not require an
Apple Developer certificate.

The signed XCTest runner retains its sandbox. Its test-only entitlements allow
a loopback response server and `/private/tmp/bedrock-ui-fixtures/`. Each case uses
a new UUID directory and removes it during teardown. This avoids opening files
from another application's private container. CI supplies the actual Python
interpreter through `BEDROCK_TEST_PYTHON`; the `/usr/bin/python3` Xcode shim
cannot run inside the test runner. For direct Xcode test runs, set the
`BEDROCK_TEST_PYTHON` build setting to the result of
`python3 -c 'import sys; print(sys.executable)'`.

If XCTest reports “Timed out while enabling automation mode”, check
`automationmodetool` without arguments. A Mac that requires authentication must
complete the normal UI-testing authentication in Xcode before the command-line
suite can run. CI reports this before launching a runner that would time out.
The validation script does not change system authentication or
accessibility permissions. This environment failure is a failed local CI run,
even when the build and non-UI tests have passed.

Synthetic key events use the available ASCII keyboard source because XCTest's
character-based Shift shortcuts depend on the active input method. Each case
restores the preceding input source at teardown, unless the user changed it
during the test. Native composer tests separately exercise marked-text and IME
handling.
