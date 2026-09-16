# Pilot → Bedrock for Mac: local Swift port

Started: 2026-09-15. Source reviewed: `/Users/sanghwa/workspaces/foxl-ai/pilot`.

The product is a native Swift/SwiftUI macOS Bedrock client. Conversations,
skills, preferences, schedules, and run history stay on this Mac.
Inference goes directly to the user's configured AWS services. User-configured
MCP connections and explicitly enabled web tools remain direct connections.
There is no Foxl account, relay, hosted agent, sync service, or telemetry backend.
Notes and meeting recording are outside this project.

An item is checked only after implementation and the validation named for that
item. A successful build alone does not prove AWS inference, a permission prompt,
or an interactive UI works. Live checks that cannot run must remain open with
the actual error recorded in `PILOT_VALIDATION.md`.

## Current design scope

The user's latest corrections take priority over the original broad port:

- Keep Demo library, Automations and Activity available in the sidebar.
- Remove Files and project selection. Local file tools accept absolute, `~/`
  and relative paths. All built-in tools and local paths are enabled by default;
  Settings can restrict individual tools, approval policy and allowed folders.
- Keep the main chat quiet: no project picker, demo starter cards, sidebar search,
  or repeated assistant model-name headings.
- Put Skills in Settings. Combine Archive and Trash in Settings → Data & history.
- Put the model selector in the composer. Preserve the original provider logos,
  search, favorite stars and compact rows; remove provider-filter controls.
- Preserve the original System/Light/Dark appearance choices and saved preference.
- Keep the Bedrock wordmark in the sidebar; no Bedrock symbol inside the app.
  Use monochrome controls with consistent native icons, type and spacing.
- Keep New chat and Settings in the sidebar only. The chat toolbar contains
  Search and chat actions; the composer contains one response-settings control.
- Center the welcome composer directly under “How can I help?”.
- Change models inside the same chat, preserving history, drafts and attachments.
- Prioritize tool inputs/results, responsive rendering and backward compatibility.

## Source map and scope decisions

| Pilot source | Native destination | Scope |
| --- | --- | --- |
| `foxl/apps/web/src/config/command-registry.ts`, `settings-index.generated.ts` | Searchable command palette and individual settings registry | Port |
| `components/layout/AppSidebar.tsx`, `lib/pinned-conversations.ts` | Native navigation, pinned threads, archive/trash, thread actions | Port |
| `components/chat/*`, `pages/ChatPage.tsx` | Composer, attachments, search, stream state, reasoning, tools, companion view | Port |
| `pages/SkillsPage.tsx`, `server/skills/*` | Local SKILL.md library, import/edit/enable, per-thread selection | Port |
| `pages/ToolsPage.tsx`, `server/tools/tool-profiles.ts`, `tool-permissions.ts` | Local tool profiles, individual switches, approvals and execution log | Port |
| `server/tools/{exec,file-write,tool-cache,tool-chain}.ts` | Bounded native process/filesystem tools and output | Port applicable behavior |
| `pages/WorkspacePage.tsx`, `shared/workspace-files.ts` | Direct local file tools and attachment previews | Adapt; Files page/project concept removed by latest request |
| `pages/SchedulesPage.tsx`, `server/scheduler/*` | Local, app-running automations with explicit limits | Port |
| `shared/token-usage.ts`, `pages/OverviewPage.tsx`, `pages/LogsPage.tsx` | Local activity, tokens, cache usage and latency | Port |
| `server/agent/{context-compaction,retry-policy,error-classifier}.ts` | Bounded context, cancellation, retry and useful errors | Port |
| `pages/SettingsPage.tsx`, `NotificationSettingsPage.tsx` | Native settings, shortcuts and desktop notifications | Port relevant rows individually |
| Browser extension, Chrome bridge | User-configured local MCP; direct web fetch/open controls | Adapt; no bundled external extension |
| Multi-provider login, hosted inference, subscription reuse | Existing AWS profiles, AWS SSO, Bedrock API key | AWS only |
| Account, billing, teams, shared skills, org policies | None | Excluded: hosted/multi-user |
| Relay, tunnel, pairing, mobile/web clients, remote machines | None | Excluded: local-only scope |
| Foxl Code fleet, AgentCore deployment, GitHub App, remote PR automation | Local files/git/shell demos | Cloud fleet excluded |
| Notes, recording, meeting summaries, note export, Notes Flow | Existing chat dictation only | Notes excluded by request |
| Slack/email/calendar channels, social publishing | Optional user-configured MCP | No bundled account integrations |
| Pet, game, marketing, status site, administrative dashboards | None | Excluded: unrelated to Bedrock demos |
| Heartbeat/webhook server/24×7 hosted daemon | Explicit local schedule while app runs | No public listener or hidden daemon |

## 1. Foundation and data integrity

- [ ] F01 Baseline Debug build captured before edits; record result.
- [ ] F02 Native app and existing test target build with the new source files.
- [x] F03 Versioned local workspace metadata; create/reload round trip. (`swift test`, 2026-09-15)
- [ ] F04 Atomic metadata/history writes; interrupted writes preserve previous data.
- [ ] F05 Corrupt imports/storage produce an actionable error and preserve source data.
- [ ] F06 Existing Core Data chats and unified/legacy histories still load.
- [ ] F07 Draft text survives thread switches and app restart.
- [ ] F08 Empty-thread cleanup preserves drafts, pins and configured threads.
- [x] F09 Legacy project IDs remain decodable; thread/automation paths migrate to working directories. (core migration regression, native 35 opens existing stores)
- [x] F10 Optional folder restrictions resolve symlinks and reject escapes; unrestricted mode accepts general local paths. (real filesystem regression tests, core 36)
- [ ] F11 Bedrock API key moves from defaults into macOS Keychain without losing the old value on failure.
- [ ] F12 No Foxl relay, sign-in, sync or telemetry dependency is introduced.

## 2. Native shell and navigation

- [ ] U01 Native resizable split view with a quiet sidebar and unified toolbar.
- [x] U02 New thread entry and empty-state composer work without existing history. (Cmd-N, focused centered composer, real Astra request; native 21/23)
- [ ] U03 Thread list groups pinned/recent items and has no fixed row-count cap.
- [ ] U04 Thread selection has stable identity and preserves active generations.
- [ ] U05 Sidebar collapse/restore and keyboard shortcut work.
- [x] U06 Demo library navigation works. (native 21; Create image → editable prompt → actual image)
- [ ] U07 Skills library opens from Settings.
- [ ] U08 Automations navigation works.
- [ ] U09 Activity/usage navigation works.
- [x] U10 Files navigation is removed from sidebar and command palette. (supersedes original Files-page item; native 35)
- [x] U11 Footer shows the actual AWS profile/region and opens configuration. (native 21/23: default, us-west-2)
- [ ] U12 Loading, empty, unavailable and error states offer working actions.
- [ ] U13 Layout works at minimum window size and a wide desktop size.
- [ ] U14 Light, dark and system appearances persist and apply on launch.
- [ ] U15 Native focus rings, readable contrast, labels and accessibility identifiers.
- [ ] U16 Reduce Motion avoids unnecessary animated transitions.
- [ ] U17 Inspector/companion pane opens, closes and resizes.

## 3. Thread actions and composer

- [ ] C01 Create a thread with the selected model; the main chat has no project picker.
- [ ] C02 Rename a thread; title survives restart and AI title generation.
- [ ] C03 Pin/unpin a thread; order remains stable as responses arrive.
- [ ] C04 Archive/unarchive a thread without deleting its history.
- [ ] C05 Move to trash and restore a thread.
- [ ] C06 Permanently delete only the chosen trashed thread and its local files.
- [ ] C07 Export selected thread as Markdown through a save panel.
- [ ] C08 Export/import versioned conversation JSON; validate malformed files.
- [ ] C09 Copy thread text without hidden tool-result rows.
- [ ] C10 Fork a conversation; copied history remains independent.
- [ ] C11 Open another thread beside the current one for reference.
- [ ] C12 Edit a previous user prompt into a new branch without destroying history.
- [ ] C13 Retry a failed response without duplicating the user message.
- [ ] C14 Regenerate an answer as a branch.
- [ ] C15 Multiline native composer grows to a bounded height.
- [ ] C16 Return sends and Shift+Return inserts a newline; Korean IME composition does not send prematurely.
- [ ] C17 Send button accurately follows input, attachments and running state.
- [ ] C18 Stop/Escape cancels the actual inference/tool operation and restores controls.
- [ ] C19 Paste/drop/import images and documents; preview/remove individual attachments.
- [ ] C20 Large pasted text uses a removable file attachment and reaches inference.
- [ ] C21 Chat dictation inserts transcript and exposes microphone errors.
- [ ] C22 Per-thread skill picker persists; selected skills affect the next request.
- [ ] C23 Slash commands insert demo prompts or invoke local actions.
- [x] C24 File access no longer needs a project; optional restrictions and working directory are in Settings. (core policy tests; native 35 Settings)
- [ ] C25 Draft typed during a response is preserved; queue/next-send behavior is explicit.
- [ ] C26 User messages, assistant prose, code, reasoning and tool results have distinct readable layouts.
- [ ] C27 Copy code/text, image save and document preview remain functional.
- [ ] C28 Auto-scroll follows output only while the user is at the bottom.
- [ ] C29 Find-in-thread navigates matches including Korean and multiline text.
- [ ] C30 Keyboard event monitors and timers are removed when views disappear.

## 4. Command palette and discovery

- [x] K01 Command+K opens one native searchable palette. (native 21, correct fixture found and opened)
- [ ] K02 Search finds pages and actions by label and synonyms.
- [ ] K03 Search finds individual settings and opens the correct row.
- [ ] K04 Search finds threads by title and message content.
- [ ] K05 Search finds skills and demo presets.
- [ ] K06 Arrow keys/Return/Escape and empty-result state work.
- [ ] K07 Every registered destination resolves; no stale settings IDs.
- [ ] K08 Search work is debounced and stale results cannot replace newer ones.
- [ ] K09 Shortcut reference lists the actual working shortcuts.

## 5. Bedrock demos and model configuration

- [ ] D01 Model catalog merges foundation models and inference profiles without dropping either.
- [ ] D02 Model refresh does not discard a usable previous catalog on error.
- [ ] D03 Model search/favorites/default selection persist and resolve to real IDs.
- [ ] D04 Text streaming demo sends a prepared prompt to the chosen Bedrock model.
- [ ] D05 Reasoning demo surfaces reasoning effort and streamed thinking.
- [ ] D06 Document Q&A demo explains required attachment and runs with it.
- [ ] D07 Vision demo explains required image and runs with it.
- [ ] D08 Structured-output demo supplies a concrete schema/prompt.
- [ ] D09 Local folder-review demo accepts a path variable and reads/searches that folder without project selection.
- [x] D10 Image generation demo selects an available compatible model. (native 21: Stable Image Core 1.0, us-west-2, actual image in 2.7s; six routing/schema regressions)
- [ ] D11 Video generation demo exposes S3 requirements before submission.
- [ ] D12 Embedding demo displays a real vector/dimensions response.
- [ ] D13 Model comparison runs the same prompt in independent threads.
- [ ] D14 Custom demo/prompt preset create, edit, duplicate, export and delete.
- [x] D15 Preset variables must be filled; user text is not treated as replacement syntax. (literal, repeated and nested-placeholder regression tests)
- [x] D16 Choosing a demo prepares an editable draft and never silently starts paid work. (native 21 image demo; explicit Send required)
- [ ] D17 Unsupported modality/tool combinations explain their limits before sending.
- [ ] D18 Streaming and non-streaming requests honor the same configured inference parameters.
- [ ] D19 Prompt caching switch changes actual requests; usage reports actual cache reads/writes.
- [ ] D20 Per-model max tokens, temperature, top-p, inclusion toggles, thinking budget, effort and reset retain meaningful validation.
- [ ] D21 Legacy Nova Canvas is absent from new model/demo choices; existing image history still opens.
- [ ] D22 Titan Image controls: task, dimensions, quality, count, cfg, seed, negative prompt and editing inputs.
- [ ] D23 Stability generation controls: model, aspect ratio, style, seed, negative prompt and output format.
- [ ] D24 Stability service controls: service-specific inputs, mask, strength, scale and output.
- [ ] D25 Active Luma Ray controls: aspect ratio, duration, resolution, loop, keyframes, output S3 URI and region; legacy Reel is absent from new choices.
- [ ] D26 Image/video progress, failure, cancellation, save and reveal use actual results.

## 6. Local skills

- [ ] S01 Discover local `SKILL.md` folders and flat Markdown skills.
- [x] S02 Parse name, description, multiline frontmatter, tags and requirements. (`swift test`, block/folded YAML and malformed-input coverage)
- [ ] S03 Import skill folders including references/scripts without executing them.
- [ ] S04 Create a skill with validated name and editable instructions.
- [ ] S05 Edit/save/reload a skill and reveal its directory in Finder.
- [ ] S06 Enable/disable state is stored outside the skill source file.
- [ ] S07 Search/filter skills by name, description and tags.
- [ ] S08 Missing binaries/environment/platform requirements are visible.
- [ ] S09 Selected skill instructions and the enabled, eligible skill catalog enter the request; other skill content loads on demand.
- [ ] S10 Skill instructions have a bounded context budget and visible truncation/error.
- [ ] S11 Per-thread skill selection survives restart.
- [ ] S12 Bundled Bedrock demo, code review, document analysis and skill authoring skills work offline.
- [ ] S13 Skill removal does not remove unrelated files or revive itself on restart.
- [ ] S14 Disabled skills cannot turn restricted tools back on.
- [ ] S15 Effective system prompt/active skills can be inspected before sending.

## 7. Local tools and MCP

- [x] T01 Tool profiles: All tools (default), Chat only, Read only, Developer, Custom. (core defaults/migration tests; native 35 actual selection)
- [ ] T02 Individual tool switches affect the actual advertised schemas.
- [ ] T03 Read file with byte/line limits and valid UTF-8 handling.
- [ ] T04 List any allowed local directory; shallow listing by default, explicit recursion/hidden controls.
- [ ] T05 Search an allowed directory with bounded output and cancellation.
- [ ] T06 Write a local file atomically, respecting optional folder restrictions.
- [x] T07 Execute a shell command with a working directory, timeout and bounded output. (native 35 actual `local_run_command`, `/tmp`, exit 0; process tests)
- [x] T08 Stop a shell process and its children; no orphan execution. (real child process cancellation regression)
- [ ] T09 Read git status/diff/log through arguments, with no shell interpolation.
- [ ] T10 Fetch a user-approved HTTP(S) URL with timeout, response limit and domain controls.
- [ ] T11 Open an approved HTTP(S) URL in the default browser.
- [ ] T12 Session status reports actual model/working directory/time and available tools.
- [ ] T13 Per-call approval shows tool name, input and target; allow/deny/cancel work.
- [ ] T14 Approval policy is persisted and checked at execution, including MCP.
- [ ] T15 Tool errors remain errors in the next Bedrock toolResult.
- [ ] T16 Multiple tool calls in one streamed answer all receive matching results.
- [ ] T17 Simultaneous threads do not share a tool-stream accumulator.
- [ ] T18 Tool-turn limit produces a visible stopped reason and retains history.
- [x] T19 Tool result display retains inputs, output, status and elapsed time. (native 35 actual shell call, inline and detail tabs; Escape close and Cmd-D sheet guard)
- [ ] T20 Local MCP add/edit/delete, enable, connect/disconnect and reconnect work.
- [ ] T21 MCP command, argument parsing, environment and working directory validate.
- [ ] T22 User-configured HTTP MCP URL, headers and OAuth controls retain existing support.
- [ ] T23 MCP config import/export rejects duplicates and invalid transports.
- [ ] T24 MCP crash recovery and unavailable server status remain actionable.

## 8. Local automations and activity

- [ ] A01 Create/edit an automation with prompt, model, optional working directory and selected skills.
- [ ] A02 Once, interval and daily scheduling calculate the next run correctly.
- [ ] A03 New automations start disabled; enabling is an explicit UI action.
- [ ] A04 Run now creates an actual Bedrock thread and records its result.
- [ ] A05 Pause/resume/delete affect future runs without erasing completed history.
- [ ] A06 Maximum runtime cancels work and records timeout.
- [ ] A07 Prevent overlapping runs and replay storms after sleep/relaunch.
- [ ] A08 App-running scheduling limitation and next-run time are visible.
- [ ] A09 Automation failures and completion link to the correct thread.
- [ ] A10 Activity persists status, model, thread, tokens, cache usage and timing.
- [ ] A11 Filter activity by status/model/date; inspect one run.
- [ ] A12 Usage aggregates match actual persisted runs and unknown usage stays unknown.
- [ ] A13 Export local activity/diagnostics without credentials or prompt bodies.
- [ ] A14 Completion/error notifications honor enable, sound and background-only settings.

## 9. Settings: every row is a separate acceptance item

Each setting must be discoverable, persist after reopening, and affect the
behavior described. Existing image/video parameter rows are expanded into the
validation inventory during their respective demo audit.

- [ ] P01 AWS region.
- [ ] P02 AWS profile, refresh and SSO status.
- [ ] P03 Bedrock API key save/remove in Keychain.
- [ ] P04 Custom Bedrock control endpoint: validate URL, commit without Return.
- [ ] P05 Custom Bedrock runtime endpoint: validate URL, commit without Return.
- [ ] P06 Connection test and model refresh.
- [ ] P07 Default model.
- [ ] P08 Model favorites.
- [ ] P09 Global system prompt.
- [ ] P10 Saved system prompt create/select/rename/delete.
- [ ] P11 Default reasoning display.
- [ ] P12 Prompt caching.
- [ ] P13 Context character/token budget.
- [ ] P14 Maximum tool turns.
- [ ] P15 Automatic title generation.
- [ ] P16 Thinking summaries (extra inference opt-in).
- [ ] P17 Appearance: system/light/dark.
- [ ] P18 Conversation text size and reset.
- [ ] P19 Compact sidebar density.
- [ ] P20 Show run usage information.
- [ ] P21 Show timestamps.
- [ ] P22 Enable Quick Access.
- [ ] P23 Quick Access hotkey recording/reset.
- [ ] P24 Return/Command+Return send behavior.
- [ ] P25 Allow image pasting.
- [ ] P26 Treat large pasted text as a file.
- [ ] P27 Restore last thread on launch.
- [ ] P28 Default working directory; `~` when unset.
- [ ] P29 Data directory choose/reveal; existing data remains accessible.
- [ ] P30 Skills directory reveal/import/refresh.
- [ ] P31 Default tool profile.
- [ ] P32 File read tool switch.
- [ ] P33 File list tool switch.
- [ ] P34 Code search tool switch.
- [ ] P35 File write tool switch.
- [ ] P36 Shell tool switch.
- [ ] P37 Git tool switch.
- [ ] P38 Web fetch tool switch.
- [ ] P39 Open URL tool switch.
- [ ] P40 Session status tool switch.
- [ ] P41 Tool approval mode.
- [ ] P42 Shell timeout.
- [ ] P43 Tool output size limit.
- [ ] P44 Allowed web domains.
- [ ] P45 Enable MCP.
- [ ] P46 MCP server connection settings, one row per field.
- [ ] P47 Local automations enabled/paused.
- [ ] P48 Native notifications enabled.
- [ ] P49 Notification sound.
- [ ] P50 Notify only when app is in background.
- [ ] P51 Check for app updates.
- [ ] P52 Launch at login.
- [ ] P53 Show menu bar item.
- [ ] P54 Debug logging (off by default).
- [ ] P55 Reveal logs.
- [ ] P56 Export diagnostics.
- [ ] P57 Archive/trash browse and restore.
- [ ] P58 Keyboard shortcuts reference.
- [ ] P59 About/version and local data explanation.
- [ ] P60 Settings search with working row destinations.
- [ ] P61 Allow all local paths; disabling exposes allowed directories.
- [ ] P62 Add/remove allowed file directories.
- [ ] P63 List skills tool switch.
- [ ] P64 Load skills tool switch.

## 10. Performance, regression and real validation

- [ ] V01 Run existing inference configuration tests.
- [ ] V02 Run local persistence/import/draft/skill tests.
- [x] V03 Run tool path, approval policy, timeout, cancellation and output-boundary tests. (core suite; UI approval checks remain T13/T14)
- [x] V04 Run scheduling, context budget and command destination tests. (core suite)
- [ ] V05 Stream UI updates are coalesced; no full disk read/write per token.
- [ ] V06 Native message rendering retains stable IDs and search navigation.
- [ ] V07 Long conversation context is bounded without modifying stored history or breaking tool pairs.
- [ ] V08 Cancelled requests do not append a generic model error or overwrite a new run.
- [ ] V09 Metadata usage is captured even when a response contains tool calls.
- [ ] V10 No accidental extra inference for empty thread/title/summary operations.
- [ ] V11 Build Debug and Release with existing supported deployment target.
- [x] V12 Launch the real native app in isolated validation storage. (native AX + screenshot, `run-workbench-preview.sh`)
- [ ] V13 Exercise sidebar, palette, settings, demos, skills, files and automations through UI.
- [ ] V14 Exercise thread create/rename/pin/archive/trash/restore/export/import through UI.
- [x] V15 Real Bedrock text stream and follow-up retain context. (native Astra/Nova conversation retains BRIDGE_42)
- [ ] V16 Real Bedrock local tool call reads a fixture and answers from actual output.
- [ ] V17 Real Bedrock cancellation and error recovery.
- [ ] V18 Real Bedrock image/embedding/video checks where configured AWS access permits.
- [ ] V19 Record exact remaining external prerequisites; never check a blocked live test.
- [ ] V20 Update README, troubleshooting, validation report and this checklist to match the implementation.

## 11. Active model scope and macOS 26 follow-up

- [ ] M01 Every active catalog ID has an explicit invocation route and validation row.
- [ ] M02 Legacy lifecycle entries and their inference profiles are absent from new choices.
- [ ] M03 Composer model picker searches provider/name/ID and groups favorites without provider-filter controls.
- [ ] M04 Model details show actual regional availability and selectable inference profiles.
- [ ] M05 Refresh/loading/offline states never mix catalogs from different connections.
- [ ] M06 Explicit custom model IDs and application profile ARNs remain usable with list permissions denied.
- [ ] M07 GPT-6 and GPT-5.6 use regional Converse profiles, including tools, images and reasoning.
- [ ] M08 GPT-5.4, GPT-5.5, Grok 4.3 and Gemma 4 use their actual Mantle endpoint.
- [ ] M09 Mantle requests use `store: false`, local conversation context, cancellation and bounded output.
- [ ] M10 Mantle tool calls and image/audio/video inputs work for each advertised capability.
- [ ] M11 Cohere v4, Titan, Nova Multimodal and Marengo embeddings return actual vectors.
- [ ] M12 Amazon/Cohere rerank demos accept documents and display actual ranked results.
- [ ] M13 Pegasus video understanding routes through InvokeModel with valid media.
- [ ] M14 Nova 2 Sonic uses bidirectional audio with visible microphone/connection state.
- [ ] M15 Stability editing/generation and Luma video routes match each active model's schema.
- [ ] M16 All configured regions are selectable; unavailable access produces recovery guidance.
- [ ] U18 macOS 26 glass/toolbar controls remain readable in light/dark and Reduce Transparency.
- [ ] U19 Page switches preserve window bounds; no header/sidebar content moves off screen.
- [ ] U20 Output follows automatically until the user scrolls away; search keeps its position.
- [ ] U21 Skills and MCP expose discovery, configuration, health, tools and execution results.

## 12. Latest chat polish and compatibility acceptance

Each control and behavior remains separate; implementation is not a live-test result.

- [x] CP01 Model selector exists only in the composer on both new and existing chats. (native 21/23)
- [x] CP02 Original provider logos, favorite stars and compact provider sections render correctly. (native picker, build 9)
- [x] CP03 No “All providers” control, route chips or extra catalog footer in the selector. (native picker, build 9)
- [ ] CP04 Search filters models without losing composer text or keyboard focus.
- [x] CP05 Selecting a model updates the visible selection and the actual next request. (native Astra → Nova follow-up returned BRIDGE_42)
- [x] CP06 Switching an existing chat preserves its ID, title and complete prior messages. (same persisted chat ID, native build 9)
- [x] CP07 Switching an existing chat preserves an unsent draft. (native draft preserved when switching Astra → Nova)
- [x] CP08 Switching an existing chat preserves unsent image/document attachments. (native model-switch.txt attachment preserved)
- [ ] CP09 Selecting during a response queues the model for the next message.
- [ ] CP10 Response settings follow the selected chat's current model.
- [ ] CP11 GPT-6 Astra custom-parameter toggle persists.
- [ ] CP12 GPT-6 Astra output limit edits persist and affect a real request.
- [ ] CP13 GPT-6 Astra output-limit inclusion toggle affects a real request.
- [ ] CP14 GPT-6 Astra Low/Medium/High/Very high/Max effort selections persist.
- [x] CP15 Astra's saved effort survives the global thinking toggle; unsupported `none` is not sent. (core regression)
- [ ] CP16 Astra has no unsupported temperature/top-p controls.
- [ ] CP17 Streaming on/off is persisted independently of custom parameters.
- [ ] CP18 Non-streaming mode still completes a tool-call cycle.
- [ ] CP19 Theme System follows the macOS appearance.
- [ ] CP20 Theme Light applies to main chat, model popover and Settings.
- [ ] CP21 Theme Dark applies to main chat, model popover and Settings.
- [x] CP22 Appearance survives application restart. (Dark preference survived build 9 → 10 restart)
- [x] CP23 Main sidebar shows the Bedrock wordmark with a normal 20-point inset; no Bedrock icon appears inside the app. (native 21/23 main and Settings)
- [x] CP24 Chats title rows have sufficient leading padding. (native sidebar, build 10)
- [ ] CP25 Send/Stop, attach, microphone and toolbar controls have circular hit areas.
- [x] CP26 No repeated model-name headings between thinking, tool use and assistant text. (native conversation, builds 9–11)
- [x] CP27 Tool cards expand to show actual input and output. (native 21 fixture; live MCP tracked separately)
- [ ] CP28 Tool details expose status, server, timing and copy actions.
- [ ] CP29 Two MCP servers with the same tool name route to the chosen server.
- [x] MG01 Released unified JSON loads without formatVersion/modelID. (core regression)
- [x] MG02 Legacy snake-case reference dates and camel-case Unix dates preserve timestamp and order. (core regression)
- [x] MG03 Image/document/pasted text/video/thinking/tool fields survive a model switch and JSON round trip. (core regression)
- [x] MG04 First unified-file upgrade preserves an exact original backup; later saves retain it. (core filesystem regression)
- [x] MG05 Corrupt, future-version and wrong-chat files cannot be replaced by an empty conversation. (core filesystem regression)
- [x] MG06 A malformed legacy message fails the whole migration rather than silently dropping records. (core regression)
- [x] MG07 Cross-model request copies omit foreign signatures and preserve tool results as context. (core regression)
- [x] MG08 Unsupported historical attachments remain stored and are represented honestly in requests. (core regression)
- [x] MG09 Released inference settings decode with defaults for newly introduced fields. (core regression)
- [x] MG10 Preference backup keeps released keys, including defaultDirector; excludes credentials and never overwrites its first snapshot. (core filesystem regression)
- [x] MG11 Existing Core Data index opens after upgrade with unchanged thread IDs and titles. (existing isolated Core Data index opened by builds 9–11)
- [ ] MG12 Reopen a migrated conversation, switch models and continue with its earlier context.
- [ ] MG13 Restart restores the selected model, theme, per-model parameters, draft and thread metadata.
- [ ] MG14 Keychain failure preserves the original credential and reports an error.
- [ ] MG15 Archive/Trash restore preserves migrated history and local metadata.

## 13. Settings input and keyboard regression pass

- [x] SI01 Models: default model selector stays inside its row and is the single way to choose the default model. (native 31, Settings → Models)
- [ ] SI02 Models: model/profile ID is read-only, copyable and integrated beneath the default model selector; no separate ID editor.
- [x] SI03 Models: response settings open for the selected default model. (native 31, Astra)
- [ ] SI04 Models: the system prompt editor wraps and scrolls without clipping its border or placeholder.
- [ ] SI05 Models: pending prompt edits save to the original preset when switching presets.
- [ ] SI06 Models: add, rename, switch and reopen prompt presets preserve their contents.
- [ ] SI07 Models: context budget and Advanced controls remain reachable at the minimum window size.
- [x] SI08 Response settings: output limit is directly editable and persists after closing the popover. (native 31: 128,000 → slider 115,200 → reopen → restore 8,192)
- [ ] SI09 Response settings: temperature, Top P and thinking budget use working native inputs/sliders.
- [ ] SI10 Response settings: disabled or unsupported parameters match the actual request.
- [ ] SI11 Response settings: reasoning effort labels fit, are selectable and persist.
- [ ] SI12 AWS: API key, profile refresh and endpoint controls have visible labels and accessible hit targets.
- [ ] SI13 All Settings panes remain readable in Light and Dark at the minimum window size.
- [ ] SI14 Tools & MCP: local and HTTP server forms keep long paths, arguments and header fields editable.
- [x] SI15 Astra: opening custom parameters at the 128,000-token range remains responsive; native tick-mark creation is removed. (native 31 numeric/slider changes and reopen; continuous-slider source)
- [ ] SI16 Numeric settings publish and persist one complete model configuration per change, including its foundation/profile alias.
- [x] KB01 Cmd-N opens New chat and focuses the composer from an existing thread.
- [ ] KB02 Cmd-N works from Settings and after the main window closes, retaining existing drafts.
- [x] KB03 Cmd-D moves the selected thread to recoverable Trash and selects the most recent remaining thread. (native 35, original draft restored)
- [x] KB04 Cmd-D does not delete a background chat while Settings or a sheet is active. (native 32, actual tool details and Settings; thread retained)
- [x] KB05 Cmd-B toggles the actual main sidebar with editor focus.
- [x] KB06 Cmd-comma opens the single Settings window; Cmd-W closes only the current window. (native 23 while Astra continued streaming)
- [ ] KB07 Cmd-K opens the command palette; Cmd-F finds text in the current thread.
- [ ] KB08 Shift-Cmd-K opens Quick Access independently of Cmd-K.
- [ ] KB09 Cmd-plus/minus/zero adjust chat text only in the main chat window.
- [ ] KB10 Settings shortcut reference matches the tested menu commands.


## 14. Scroll, monochrome controls, and menu regression

- [x] UI01 Import a 60-message local fixture through File → Import Thread; preserve its text, tables, code, thinking and tool metadata. (native build 14)
- [x] UI02 Scroll the long fixture in both directions and reach both ends without a main-thread stall. (36 wheel actions; build 14, 18 process samples)
- [x] UI03 Code highlighting loads from bundled assets and Copy code returns the original text. (build 14, SCROLL_01 copied into composer)
- [x] UI04 Tool detail Input/Output tabs and Done work; JSON booleans and numbers remain intact. (build 14 fixture; live MCP is tracked separately)
- [x] UI05 Dark-mode navigation/toolbar icons are white; the enabled Send button has a white circle and black arrow. (build 16 native screenshot)
- [x] UI06 Welcome and Settings have no Bedrock symbol; unknown model providers use a neutral symbol. (source/build 16; Settings visual check pending)
- [ ] UI07 Disabled, enabled and Stop states remain readable in Light and Dark.
- [x] UI08 Resize the main window and adjust chat font size without clipping the long reply's final paragraph. (native 32, two font increments/reset and 1080×740 → 903×655 → 1080×740)
- [ ] MN01 App menu: Settings and Quick Access open their correct windows; closing either preserves the main thread.
- [ ] MN02 File menu: New Thread, Import Thread and recoverable Trash perform their actions; disabled states follow the focused window.
- [ ] MN03 View menu and Cmd-K open the command palette; search, keyboard navigation and activation work.
- [ ] MN04 Chat options: rename, pin/unpin, branch and copy work on an isolated fixture.
- [ ] MN05 Chat options: Markdown/JSON export and subsequent import preserve content.
- [ ] MN06 Archive and Trash restore work from Settings → Data & history.
- [ ] MN07 Composer model menu: search, favorites, inference route and Use by default work and persist.
- [ ] MN08 One composer response-settings control opens the current model's text/image/video settings; tool-schema inspection is available in Settings → Tools & MCP.
- [ ] MN09 Demo library: categories/search, create/edit/duplicate/import/export and Use prompt work.
- [x] MN10 Files menu/page is removed; direct file tools and attachment actions remain. (supersedes original Files-page scope; native 35)
- [ ] MN11 Automations: create/edit/duplicate, pause/resume, Run now, Stop and View run work.
- [ ] MN12 Activity: filters, run details and export work.
- [ ] MN13 Settings: General, Appearance, AWS connection, Models, Skills, Tools & MCP, Keyboard, Data & history and Advanced remain reachable and fit their window.
- [ ] MN14 Settings search opens and highlights the correct control.
- [ ] MN15 System-prompt preset menu: add/rename/switch; compact name/chevron spacing and saved content.
- [ ] MN16 MCP forms: stdio and HTTP configuration, connection state and actual tool details work.
- [ ] MN17 Help menu opens the Bedrock documentation; Window commands keep the app responsive.
- [ ] MN18 Menu bar item opens the main app, Quick Access and Settings.

The menu pass found a separate shared-state bug: an explicit `ObservableObjectPublisher` disconnected `@Published` navigation/sheet properties from view updates. A standalone Combine reproduction emitted zero notifications with the explicit publisher and one with the synthesized publisher. The store now uses the synthesized publisher while retaining guarded draft batching; native revalidation follows in build 17.

## 15. Markdown, stream performance, and simplified controls

- [x] RP01 Keep native Markdown bounded to 4,000 UTF-8 bytes and 48 blocks; use the original WebKit path for long replies. (native 31/32; supersedes the unbounded-native experiment)
- [x] RP02 Streaming content renders Markdown before the response completes. (native 23 live Astra screenshot with Stop response visible)
- [x] RP03 Open/closing code fences preserve earlier paragraphs and exact code text. (native renderer XCTest)
- [x] RP04 Nested lists preserve numbering, indentation and continuation paragraphs. (native renderer XCTest and native 23/24 screenshots)
- [x] RP05 Tables and quotes retain separate structure. (native renderer XCTest)
- [x] RP06 Cached layout reflows at 720 → 420 → 720 points and restores the original height. (420-row NSHostingView test, 0.17s initial run; 0.42s repeat during a build)
- [ ] RP07 Long live responses remain responsive when repeatedly scrolling away from and back to the end.
- [ ] RP08 The end of a growing response never leaves an estimated blank area.
- [ ] RP09 Stop preserves the last buffered output; a following request does not receive stale chunks.
- [x] RP10 Model selection during a response applies to the next send and preserves its draft. (native 31: Astra running → select Nova → preserved draft → actual Nova `NEXT_MODEL_OK`)
- [ ] RP11 Font changes, window resizing and Light/Dark switches preserve correct cached heights.
- [x] RP12 Welcome composer is centered directly under “How can I help?”. (native 21/23)
- [x] RP13 A prepared empty demo uses the same centered welcome layout. (native 32, local-folder demo)
- [x] RP14 New chat and Settings each have a single main-window location in the sidebar. (native 21/23)
- [x] RP15 Composer has one response-settings control; extra Add and toolbar media-settings controls are removed. (native 21/23)
- [x] RP16 AWS settings no longer retain a gray row-search highlight; API key field is full width and readable. (native 23)
- [ ] RP17 AWS region/profile and media option menus remain readable, selectable and unclipped at minimum width.
- [ ] RP18 Image-editing demos validate required source images/masks before consuming the draft or sending a request.
- [ ] RP19 Luma duration, resolution, aspect ratio, loop and keyframe settings reach a real async request and local video result. (schema tests pass; live S3 run pending)
- [ ] RP20 Friendly request errors show concise recovery text and retain the original details on expansion.
- [x] RP21 A font change returns the actual HTML extent without depending on an offscreen animation frame. (native 32 font/width round trip; real offscreen WebKit XCTest)
- [x] RP22 Local-folder demo advertised listing/reading and completed a review. (native 32 actual calls; replaced project attachment with path variable in native 35; new path-variable UI check remains D09)
- [x] RP23 Actual tool calls expose their original Input and Output in an expandable row and a detail sheet. (native 32, README input/path and fixture contents)
- [x] RP24 Find uses valid UTF-16 ranges for emoji/accented/Korean text and invalidates cached results after message changes. (three search XCTest cases)
- [x] RP25 WebKit Find counts across paragraphs and code, matches text across inline markup, and clears its marks. (real WebKit XCTest)
- [x] RP26 Native Find scrolls the selected long reply's exact match into view; next/previous and closing Find preserve usable scrolling. (native 36: 28 matches, wrap to `CANCEL_LIVE_026`, previous `025`, next/wrap and Done)

## 16. Skills, permissive tools, paste and loading recovery

- [x] LT01 Fresh preferences enable all eleven built-in tools and allow their execution. (core 36)
- [x] LT02 Untouched older Chat-only defaults migrate; explicitly chosen restrictive profiles remain intact. (core 36)
- [x] LT03 Both native validation apps are set to All tools / Allow enabled tools / all local paths. (native 35 Settings)
- [x] LT04 `local_list_skills` lists actual enabled skill IDs, English names and descriptions. (native 35 actual tool call)
- [x] LT05 `local_read_skill` loads `code-review` instructions and its reference directory. (native 35 actual tool call)
- [x] LT06 `local_run_command` executes `/usr/bin/printf` in `/tmp` without an approval dialog and returns `EXEC_VALIDATED_35`, exit 0. (native 35)
- [x] LT07 Old bundled code-review instructions migrate only when unedited; custom skill content remains unchanged. (core 36)
- [x] LT08 Absolute, relative, home, root and optional restricted paths behave correctly, including sibling-prefix and symlink escapes. (core filesystem tests)
- [x] LT09 Actual shell/Git relative working-directory arguments resolve from the configured directory. (native 40: relative `/bin/pwd`, Git status, file write/read in the isolated `tool-cwd-fixture`; `RELATIVE_CWD_40` round trip)
- [x] LT10 Model answers an ordinary “which skills/tools?” question with actual IDs without being told tool names. (native 40: actual List skills call, five installed skills and the eleven exact local tool IDs; no invented namespace/parallel wrapper)
- [x] PB01 Plain clipboard text bypasses the synchronous attributed-HTML importer. (actual NSTextView test)
- [x] PB02 HTML-only paste preserves text/image ordering; malformed/oversized HTML remains bounded. (core/native tests)
- [x] PB03 Mixed plain/HTML/multiple PNG input preserves exact text and image order. (actual NSTextView test)
- [x] PB04 ImageIO preparation bounds dimensions/bytes and keeps small previews separate from request data. (native test, 3200 → 2560 pixels)
- [x] PB05 File selections prepare images/documents off the main actor, preserving repeated-selection order. (native test)
- [x] PB06 Clearing attachments cancels pending imports without cancelling later imports. (native test)
- [x] PB07 Stable attachment IDs survive removal, copying and new additions. (native test)
- [x] PB08 Real browser copy of 240 paragraphs and ten images pastes, previews and reaches inference without a stall. (native 36: 34,944 UTF-8 text bytes, ten 1600×900 PNGs; 11 attachments, full preview/Escape, Nova 2 Lite returned `PASTE_END_36`; persisted images and text verified)
- [ ] PB09 Real file picker/import/drag/drop remain responsive; Send waits for preparation.
- [ ] PB10 Quick Access uses the same bounded file path, full preview and scoped Escape handling.
- [x] LD01 Cold history reads preserve legacy/unified data, reject corrupt/future/oversized files, and honor cancellation. (core 36)
- [x] LD02 Actual cold opening of the long chat stays responsive and restores all content. (native 36 cold launch, complete long WebKit replies including final `CANCEL_LIVE_026`, Find/copy/scroll)
- [ ] LD03 Startup cleanup skips large histories and preserves the selected/drafted/pinned/archived/trashed/renamed conversation.
- [x] HS01 Rendered HTML removes scripts, event handlers, frames and active links while retaining ordinary Markdown and code. (real WebKit test)
- [x] HS02 External navigation rejects local files, application URLs, JavaScript/data URLs and credentialed web URLs. (core 36)
- [x] HS03 The actual app's CSP-protected WebKit page displays long replies, code-copy controls and search correctly. (native 36, long-history Find and exact Swift code copied into the composer)

## 17. White appearance and sidebar refinement

- [x] WS01 Light sidebar and Settings use a white background; dark appearance retains its own semantic surfaces. (native 37–42, explicit Light/Dark/System round trip in 41)
- [x] WS02 Light window toolbar, Settings search and input fields follow the white surface palette. (native 38/40)
- [x] WS03 New chat, Demo library, Automations and Activity stay fixed while only chat history scrolls; the account/settings footer stays fixed. (native 38/40)
- [x] WS04 The sidebar scrollbar has a clear track and slim rounded thumb with the current Always-visible macOS setting. (native 41: white/dark; drag from bottom to top changed the sidebar value from 1 to 0 while the conversation stayed at 0.9703)
- [x] WS05 Light/Dark/System switch without losing the selected thread, draft or usable sidebar contrast. (native 41: exact `THEME_DRAFT_41` retained; System and normal spacing restored, test draft cleared)
- [x] WS06 Sidebar wheel scrolling, thumb dragging, list keyboard navigation and collapse/expand still work. (native 41 wheel/drag; native 42 consecutive Down/Up retain list focus, ⌘B hide/show, New chat button and ⌘N/⌘D)
- [x] WS07 Settings search, no-results recovery and long forms remain readable on the white background. (native 41: model results, no-match query/Clear search, AWS and Models inspection)
- [x] WS08 Compact sidebar uses consistent row spacing and keeps the fixed navigation accessible. (native 41 compact on/off, dark/light screenshots)
- [ ] WS09 Independently exercise macOS automatic scrollbar fading and accessibility Increase Contrast. System-wide preferences were not changed during this pass.

## 18. Full Foxl convenience re-audit

See [FOXL_CONVENIENCE_TODO.md](FOXL_CONVENIENCE_TODO.md) for the source-backed chat/composer, search/history, skills/tools, MCP/model, automation and native-settings gaps. [FOXL_SETTINGS_INVENTORY.md](FOXL_SETTINGS_INVENTORY.md) maps all 129 indexed Foxl settings plus nine dynamic Appearance controls individually. Build 42 is the baseline; only demonstrated new passes are checked in the audit.
