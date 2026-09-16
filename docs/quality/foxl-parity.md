# Foxl convenience audit — native Bedrock

Audit started 2026-09-16. Reference checkout: `~/workspaces/foxl-ai/pilot/foxl`, with shared chat components in `~/workspaces/foxl-ai/pilot/packages/ui`. This is a source comparison, not a claim that every Foxl feature has passed runtime testing.

The native app keeps direct AWS inference and local data. Notes, projects, the Files sidebar, organization accounts, relay/sync, billing, social channels and the desktop pet are outside the requested scope. Demo library, Automations and Activity remain. Skills and combined Archive/Trash stay in Settings. Main-window controls remain monochrome, with the model picker in the composer.

An unchecked item means implementation or verification remains. “Existing” means a code path exists, **not** that it passed this audit. Check an item only with the implementation and relevant validation evidence. This checklist supplements, rather than replaces, `PILOT_LOCAL_PORT_TODO.md`.

## Chat and composer

Foxl evidence: `apps/web/src/components/chat/SingleMessage.tsx`, `apps/web/src/pages/ChatPage.tsx`, `apps/web/src/hooks/useStreamingChat.ts`, shared `chat-message.tsx` and `chat-prompt-input.tsx`.

- [x] FC01 Edit a sent user message and send the revision, keeping the original conversation recoverable.
- [x] FC02 Preserve images, documents and pasted-text blocks when editing or retrying.
- [ ] FC03 Retry a failed, stopped or completed response without manually copying its prompt.
- [x] FC04 Branch from a particular message, preserving complete tool-call/result pairs.
- [ ] FC05 Open the parent conversation from a branch.
- [ ] FC06 Inspect a message's actual model and timestamp on demand without repeating model headings in the transcript.
- [x] FC07 Queue a next prompt while a response is running, using the existing Send-button position.
- [x] FC08 Queue attachments together with text and the chosen next model.
- [x] FC09 Inspect, edit and remove queued prompts.
- [x] FC10 Interrupt and send a queued prompt; never overlap two runs in one conversation.
- [x] FC11 Pause the queue after a failed/stopped run and explain how to resume.
- [x] FC12 Restore queued work after relaunch without silently starting new paid requests.
- [x] FC13 Preserve the current unsubmitted draft while a queued request starts.
- [x] FC14 Restore unsent attachment drafts after relaunch. Ordinary-chat restoration and real image/document inference passed on 64; welcome restoration and inference passed on 70.
- [x] FC15 Navigate slash suggestions with Up/Down/Return/Escape without breaking Korean/Japanese IME composition.
- [x] FC16 Select an enabled local skill directly from the composer using its real identifier.
- [ ] FC17 Show selected skills as removable, compact composer chips. Reopened: hosted UI testing found the remove glyph had an 8×8 hittable area. The 24×24 hit-target correction is implemented; the actual click must pass again.
- [x] FC18 Edit a pasted-text attachment before sending, preserving its stable attachment identity.
- [ ] FC19 Keep attachment preparation cancelable and display failures without consuming the draft. Existing serial importer; repeat real file-picker/drop checks.
- [ ] FC20 Preserve scroll position while streaming, switching threads and changing layout. Existing renderer/scroll work; continue targeted regression.
- [x] FC21 Restore the previous per-thread scroll position rather than always jumping to the end. Three consecutive Activity → Back round trips retained the exact native anchor offset on 70.
- [x] FC22 Preserve exact code-copy text and Markdown structure. Existing tests; retain them as regressions.
- [ ] FC23 Offer a clear “continue” action for output-limit truncation, with actual stop-reason evidence.
- [ ] FC24 Keep context reduction visible and offer a real summary-based compaction workflow; current code only bounds history.

## Search and history

Foxl evidence: `apps/web/src/hooks/useSearch.ts`, `lib/history-cache.ts`, `lib/history-sync.ts`, `config/command-registry.ts`, `ChatPage.tsx` global-search navigation.

- [x] FH01 Global results show the matching text, not just the chat title/model.
- [x] FH02 Opening a content result opens Find and scrolls to the matched passage.
- [x] FH03 Search handles both released legacy history and unified history.
- [x] FH04 Bound file reads, cancel stale searches and cache unchanged files off the main actor.
- [ ] FH05 Search exposes progress and distinguishes a failed/unreadable history from a genuine no-match result.
- [ ] FH06 Search text inside pasted-text attachments and tool output, and open the relevant detail.
- [x] FH07 Branch/copy/export never substitute an empty history after a read error.
- [x] FH08 JSON export preserves all supported message/attachment/tool metadata and reports missing local image bytes.
- [x] FH09 Import/encode/export large conversations off the main actor.
- [x] FH10 Markdown export includes pasted text and tool input/output, plus attachment names.
- [x] FH11 Import validates versions, IDs, attachment metadata, sizes and local-reference boundaries.
- [ ] FH12 Archive/Trash search and restore retain drafts and parent/skill metadata. Existing; exercise through native Settings.
- [ ] FH13 Batch restore and Empty Trash belong only in Settings, with explicit permanent-delete confirmation.
- [x] FH14 Existing ⌘N/⌘D/⌘B/⌘K/⌘F/⌘, behavior remains intact with new message sheets and menus.

## Skills and tools

Foxl evidence: `apps/web/src/pages/SkillsPage.tsx`, `ToolsPage.tsx`, `server/skills`, `server/tools/registry.ts`, `exec.ts`, `terminal.ts`, `tool-cache.ts`, `tool-permissions.ts`, `custom-tools.ts`, shared `chat-tool-output-refs.tsx`.

- [x] FS01 Explain automatic on-demand skill loading accurately; remove stale “available only when selected” wording.
- [x] FS02 Search skills by raw identifier as well as name, description and tags.
- [x] FS03 Show malformed-skill diagnostics even when no valid skills remain.
- [ ] FS04 A deep link to a skill reveals and scrolls to that skill.
- [ ] FS05 “Use in chat” applies a skill and returns to the composer with the draft intact.
- [ ] FS06 Import/reload large skill folders off the main actor with cancellation and bounded reads.
- [x] FS07 Inspect bundled references and prerequisites from the skill detail.
- [x] FS08 Import/export skill folders without executing their contents or overwriting an existing skill.
- [ ] FT01 Add a local image-view tool so an agent can inspect images created/read with file tools.
- [ ] FT02 Expose local conversation search to the agent without introducing Notes or cloud search.
- [ ] FT03 Let the agent list/create/update local automations using the same validated scheduler as Settings.
- [ ] FT04 Add bounded background-process start/poll/stop if a command outlives a tool turn.
- [ ] FT05 Keep raw tool IDs, original input/output, timing and errors inspectable. Existing detail sheet; recheck new tools.
- [ ] FT06 File-producing tool results offer explicit Open/Reveal/Copy path actions.
- [ ] FT07 Long tool output is searchable and copyable without blocking the transcript.
- [ ] FT08 Custom shell/HTTP tools can be configured in Settings without editing app source.
- [ ] FT09 Custom tool import previews additions/replacements and omits secrets on export.
- [x] FT10 Fine-grained allow/ask/deny rules remain optional; untouched installations retain permissive defaults.
- [ ] FT11 Cache only eligible read operations, invalidate after writes and retain cancellation/output bounds.
- [x] FT12 Read-only Git inspection reports the actual cwd and respects its tool enablement/approval controls. Like shell execution, Git is not sandboxed by the optional file-tool allowlist.

## MCP, models and run recovery

Foxl evidence: `server/tools/mcp-client.ts`, `mcp-tool-text.ts`, `tool-name-collision.ts`, `server/agent/retry-policy.ts`, `model-fallback.ts`, `context-compaction.ts`, `tool-result-images.ts`.

- [ ] FM01 MCP stdio and HTTP forms preserve arguments/env/headers and show actionable connection failures. Existing.
- [x] FM02 Reconnect one server without restarting healthy servers or interrupting another conversation.
- [ ] FM03 Inspect and enable/disable each MCP tool, including nested schemas and duplicate names. Existing schema/identity handling; verify controls.
- [ ] FM04 MCP JSON import/export preserves non-secret configuration and previews replacements. Existing; check failure/round-trip behavior.
- [x] FM05 Cancel pending MCP calls and recover a disconnected server without leaving a run stuck.
- [ ] FM06 Render MCP image results and make them available to vision-capable models.
- [ ] FM07 Retry transient inference failures with bounded backoff and a visible Cancel action; do not replay completed side effects.
- [ ] FM08 Optional fallback models retain Bedrock provider/model identity and report the model actually used.
- [x] FM09 Mid-chat model switches preserve drafts, complete tool cycles, attachment compatibility and per-model parameters. Existing; retain regression.
- [ ] FM10 Keep legacy models excluded and show only valid inference routes for demos. Existing catalog/routing; live specialty-image coverage remains.
- [ ] FM11 Show the actual context/usage/stop reason in one compact run detail, without adding a toolbar HUD.
- [ ] FM12 Separate a per-turn token budget from maximum output and maximum tool turns when the provider supports it.

## Automations, activity and native settings

Foxl evidence: `apps/web/src/pages/SchedulesPage.tsx`, `LogsPage.tsx`, `SettingsPage.tsx`, `components/settings/ShortcutsSection.tsx`, `apps/electron/main.js`.

- [ ] FA01 Create/edit/duplicate/run/stop a local automation and open its resulting conversation. Existing; native verification remains.
- [ ] FA02 Offer day-of-week/active-hour scheduling with timezone and next-run preview.
- [x] FA03 Make missed-run/restart behavior explicit; never silently overlap a recurring job.
- [ ] FA04 Filter Activity by model/status/date and inspect the original error/tool timings.
- [ ] FA05 Aggregate actual token usage per model and over time without presenting guessed prices as measured cost.
- [ ] FA06 Retry a failed automation from Activity while retaining the original run record.
- [ ] FN01 Separate response-success, response-error, automation-success and automation-error notification preferences.
- [ ] FN02 Notification preview bypasses “background only” filtering and opens the intended conversation.
- [ ] FN03 Follow macOS Reduce Motion/Increase Contrast/Reduce Transparency consistently.
- [ ] FN04 Review every native settings control at minimum width in Light/Dark/System.
- [ ] FN05 Preserve existing app shortcuts; make shortcut reference searchable and offer rebinding without conflicts where supported.
- [ ] FN06 Localize visible app UI and settings (including system-language following).
- [ ] FN07 Keep launch-at-login, menu-bar access, Quick Access and update checks functional. Existing; runtime verification remains.
- [ ] FN08 Offer local diagnostic export and an issue-report action with no credentials or prompt contents.

## Settings inventory

The separate `FOXL_SETTINGS_INVENTORY.md` maps every row in Foxl's generated settings index and its additional Appearance controls. “Excluded” is a scope decision, not an implementation pass.

## Validation record

Builds 45–52: actual edit/branch and queue/relaunch checks, cross-message Markdown selection, slash skills and AWS-backed local tool execution. In one conversation, Nova 2 Lite ran a local command and GPT-6 Astra correctly recalled its output after a model switch. Build 52 app integration suite: **55 tests, 4 opt-in public-network tests skipped, 0 failures**. Separate core suite: **82 passed**. Renderer/paste suite: **30 passed** (overlaps the app suite; do not add these counts as unique tests).

Local MCP fixtures execute real stdio processes and cover duplicate tool names, structured/multimodal response serialization, stderr backpressure, literal arguments, timeout, rapid cancellation and reconnect. Remote MCP endpoints and every model/region were not live-tested. New UI work below requires another build and real-window verification. Detailed evidence is maintained in `PILOT_VALIDATION.md`.


## Latest interface and documentation follow-up

User changes received September 16, 2026. Implementation and runtime verification are separate; keep unfinished items unchecked.

- [ ] UX01 Animate ⌘B and the sidebar button consistently, including Reduce Motion.
- [x] UX02 Place Back immediately after the sidebar toggle; skip unavailable/deleted conversations and preserve drafts.
- [x] UX03 Restore global Search to the original upper-right toolbar location and size; ⌘K opens the same search. The later user correction supersedes placement beside the wordmark.
- [x] UX04 Keep in-conversation Find on ⌘F without a duplicate toolbar search icon.
- [x] UX05 Show a bounded recent transcript first; load earlier/newer messages without changing scroll anchors. Actual prepend/trim checks retained the pixel offset with no more than 96 rendered messages.
- [x] UX06 Search the full conversation, including messages outside the initial rendered page.
- [ ] UX07 Use one custom button/menu/segmented-control design in Settings and response, image and video controls.
- [ ] UX08 Verify keyboard navigation, search, selection, Escape and long values in custom dropdowns.
- [ ] UX09 Use blue selected states for enabled parameters while keeping action icons monochrome.
- [ ] UX10 Remove the opaque right-hand scroll track; match Light/Dark scrollbar styling.
- [x] UX11 Keep contextual selection menus limited to relevant copy/edit operations in native text and HTML responses.
- [x] UX12 Draw rounded inline-code backgrounds around glyphs without long gray bands.
- [x] UX13 Keep list markers outside selectable text while preserving multi-item selection and source Markdown copy.
- [ ] UX14 Match Foxl's compact flat message queue; edit/remove/send-now, pause/recover and retain attachments/model.
- [x] UX15 Capture fresh Light/Dark hero screenshots from the final running app using dedicated demonstration data.
- [x] UX16 Capture an animated main demo of actual app interaction, with an accessible static fallback.
- [x] UX17 Rewrite README around verified workflows, current screenshots, setup, shortcuts and local storage/inference boundaries.
- [x] UX18 Document reproducible visual capture and validation; link CI, tests, dependency changes and known limits.
- [x] UX19 Relaunch updated app builds and preserve existing conversations and unsent work.
- [x] UX20 Dismiss global search on outside click and Escape while protecting the underlying draft.
- [x] UX21 Keep a single thin sidebar toggle and Back in the sidebar titlebar; remove duplicate controls and permanent shading.
- [ ] UX22 Start expanded at a usable default sidebar width and prevent title/profile/region wrapping.
- [x] UX23 Extend the Settings sidebar through its titlebar to match the main window.
- [x] UX24 Add a faint 1px composer border in Light and Dark.
- [ ] UX25 Reconcile every user request in `USER_REQUIREMENTS.md` with implementation and validation evidence.
- [ ] UX26 Reorganize the repository into standard source/test/configuration directories and remove verified dead code/resources.

## September 16 completion audit

[TODO_AUDIT.md](todo-audit.md) reconciles the latest ledger with actual execution. UX02/UX21 use the native toolbar/navigation evidence; UX15–UX18 use the newly captured optimized-app media and documentation validation; UX23/UX24 use actual Light/Dark Settings and composer captures. FC17 is reopened after a hosted interaction failure. Missing features remain unchecked even when neighboring infrastructure passes.
