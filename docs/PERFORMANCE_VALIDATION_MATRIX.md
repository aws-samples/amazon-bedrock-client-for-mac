# Performance app regression matrix

The latest user request prioritizes speed and usability and asks to return to **Bedrock Validation with the latest changes included**. Compare the old Validation 50 and newer Performance 61 under the same workload, correct measured regressions, and verify the updated Validation executable. Existing data is backed up before replacement. Synthetic test conversations remain separate from existing user work.

An unchecked scenario still needs the stated runtime check. Automated suites supplement these checks; optional network tests and Xcode UI tests that could not run locally are reported separately.

## Window, navigation, and appearance

- [x] PV01 Launch the updated Validation executable and reopen existing conversations without losing history or drafts.
- [ ] PV02 Start with a usable expanded sidebar; verify minimum/default window dimensions and resize limits.
- [x] PV03 Verify one compact sidebar toggle and adjacent Back button, matching optical stroke weights, and no permanent background.
- [x] PV04 Open/close the sidebar by click and ⌘B; confirm animation, removed hidden controls, and retained conversation/draft.
- [x] PV05 Navigate Back by click and ⌘[ across chats and retained pages without losing drafts.
- [x] PV06 Verify Light, Dark, and System in both main and Settings windows.
- [x] PV07 Verify the Settings sidebar reaches through the titlebar to the top edge in both themes.
- [ ] PV08 Verify thin sidebar/transcript/settings scrollbars without opaque tracks.
- [ ] PV09 Verify the welcome heading/composer alignment, faint border, circular Send target, and enabled/disabled states.

## Search and commands

- [x] PV10 Open global Search from the original upper-right toolbar and ⌘K; verify it is centered.
- [x] PV11 Dismiss global Search with outside click and Escape; confirm keyboard focus and draft preservation.
- [x] PV12 Search message content, navigate with arrows/Return, and open a matching passage in the full conversation.
- [ ] PV13 Use ⌘F for in-chat Find, navigate matches, and close without opening global Search.
- [x] PV14 Verify ⌘N creates a distinct conversation with the current model and preserves the previous draft.
- [x] PV15 Verify ⌘D moves a chat to recoverable Trash and selects the expected preceding chat.
- [ ] PV16 Verify ⌘, and all retained main-window menu actions.

## Chat, attachments, and rendering

- [ ] PV17 Open a long existing chat, scroll repeatedly, resize, and move between threads without hangs or flicker.
- [x] PV18 Load earlier/newer pages in a large fixture while keeping the viewport bounded and anchors stable.
- [x] PV19 Paste long multilingual text and browser HTML; inspect the exact ending, edit it, and remove it.
- [ ] PV20 Paste multiple large images and mixed text/image contents; inspect/remove attachments and cancel preparation.
- [x] PV21 Restore welcome and ordinary-chat text/attachment drafts after graceful restart.
- [ ] PV22 Render headings, lists, nested lists, quotes, tables, links, code blocks, and inline code.
- [ ] PV23 Select/copy across multiple list items; keep bullets out of selectable text and preserve exact Markdown/code copying.
- [ ] PV24 Inspect sanitized right-click menus on composer and assistant text.
- [x] PV25 Repeatedly open/zoom/reset/copy/save/close large generated images; verify original export bytes.
- [ ] PV26 Edit, retry, branch, inspect message details, and open the parent conversation.
- [ ] PV27 Queue text/attachments/model/skills; edit/remove/send-now, stop, pause, resume, and restore after restart.
- [ ] PV28 Keep reading position and drafts stable during streaming and queued sends.

## Models, demos, and tools

- [ ] PV29 Refresh the actual AWS model catalog and verify Default model, immutable IDs, search, favorites, and long-name layout.
- [x] PV30 Invoke a representative text model, switch to GPT-6 Astra in the same chat, and verify context/tool replay.
- [ ] PV31 Verify inference parameters and system-prompt controls with custom menus and blue enabled states.
- [ ] PV32 Open every retained Demo library preset and validate its model/input requirements before invocation.
- [ ] PV33 Run representative text, image-generation, embedding, and comparison demos; report account/model-specific limits honestly.
- [x] PV34 Discover/load actual skills and run a harmless local command through a real Bedrock tool loop.
- [ ] PV35 Inspect tool name, original input/output, timing, errors, output search/copy, and file Open/Reveal/Copy path.
- [ ] PV36 Exercise local MCP connection, tool listing/selection, invocation, cancellation, timeout, and reconnect.
- [x] PV37 Verify permissive defaults and opt-in path/tool restrictions with an isolated file fixture.

## Settings, history, and automation

- [ ] PV38 Open all nine Settings panes at minimum width and normal width in both themes; inspect every registered control.
- [ ] PV39 Exercise non-destructive settings changes and confirm persistence; keep credential values out of evidence.
- [ ] PV40 Import/create/edit/enable/export/reload a skill and return to the intended chat.
- [ ] PV41 Inspect MCP server/tool settings and import/export previews without replacing existing configurations.
- [ ] PV42 Search/restore Archive and Trash, including multi-selection; inspect permanent-delete confirmation without deleting user history.
- [ ] PV43 Export/import a conversation and compare text, attachments, models, tool pairs, and metadata.
- [ ] PV44 Create/edit/duplicate/run/stop an isolated automation and open its resulting conversation.
- [ ] PV45 Verify Activity filters, run details, usage, failures, and links to the originating chat.
- [ ] PV46 Verify restart/missed-schedule/non-overlap behavior without silently starting paid requests.

## Build and regression evidence

- [ ] PV47 Rebuild after the final source changes and verify Xcode file/resource membership and preserved app identity.
- [x] PV48 Run core, native Markdown/clipboard/image, inference, migration, and local MCP suites with precise counts.
- [x] PV49 Type-check updated UI tests and validate CI workflows; distinguish locally executed tests from pending hosted CI.
- [ ] PV50 Repeat failed scenarios after correction, preserve measured evidence, and leave the updated Validation app running.
- [x] PV51 Compare Validation 50 and the updated app with the same 1,000-message fixture, window size, and input/scroll probes.
- [ ] PV52 Verify ordinary short chats, cold/warm history loading, and streaming separately from network/model latency.
- [x] PV53 Prevent focused menu/shortcut updates from rebuilding the app scene during typing and scrolling. Release 61→62 comparison and profiler evidence are recorded in [PERFORMANCE.md](PERFORMANCE.md).

## Issues found during this pass

- Native 57: Settings' full-height background covered the native title and window controls. Native 58 constructs the window with its final style before attaching the SwiftUI host; actual Dark screenshots show the corrected titlebar.
- Native 58: All nine settings panes were inspected in Dark at 850×700 and Light at 740×650, with no horizontally clipped controls. Closing Settings then reproducibly terminated the process with signal 11. Native 59 fixed window ownership; six actual close/reopen cycles and the lifecycle regression passed.
- Comparison 62: both builds opened the same 1,000-message fixture at 1240×780. Old Validation 50 measured typing median 73.03ms/p95 81.52ms; Performance 61 measured median 261.88ms/p95 280.26ms. These are event-to-AX text update measurements, not frame times. The six-second scroll probe took 6.05s on 50 and exceeded 20s on 61.
- Profiling 61 showed repeated SwiftUI scene, menu, and view-graph updates. Build 62 moved focused command observation from `App` into its own `Commands` value. The same Release workload measured typing median 8.59ms/p95 13.99ms afterward; the scroll probe completed in 5.99s. Replacing the old Validation executable while retaining its data produced median 7.19ms/p95 12.43ms.
- Runtime 62 found ambiguous toolbar accessibility labels and inherited popover identifiers. Actual ⌘B worked; the accessibility names were stale. The follow-up corrects semantics and keeps input/scroll performance checks in the matrix.

Runtime evidence belongs in [PILOT_VALIDATION.md](PILOT_VALIDATION.md). The complete user request ledger remains [USER_REQUIREMENTS.md](USER_REQUIREMENTS.md).
