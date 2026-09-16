# User requirements and completion ledger

Last updated: 2026-09-16. This is the authoritative checklist for the requested rebuild. Each checkbox requires both implementation and relevant verification; a code path, screenshot, or passing build alone is not proof that a feature works. The detailed Foxl audit is in [FOXL_CONVENIENCE_TODO.md](FOXL_CONVENIENCE_TODO.md), every source settings row is mapped in [FOXL_SETTINGS_INVENTORY.md](FOXL_SETTINGS_INVENTORY.md), and measured evidence belongs in [PILOT_VALIDATION.md](PILOT_VALIDATION.md).

## Final decisions that supersede earlier requests

| Topic | Final requested behavior |
|---|---|
| Product | Swift macOS client with direct Bedrock inference and local storage; no hosted Foxl backend, relay, cloud sync, Notes, or account/billing system |
| Main navigation | Keep Demo library, Automations, Activity, and Chats. Remove Files and Projects. Skills belong in Settings. |
| History management | Archive and Trash share one Settings section; neither is a main navigation destination. |
| Theme | Light, Dark, and System. Light is predominantly white with a slightly gray frosted sidebar. Dark retains the simple black design. |
| Branding | Bedrock wordmark only in the sidebar; no Bedrock pictogram inside the application. Provider identity may appear in the model picker. |
| Search location | Restore the original upper-right toolbar Search button and size. It opens a centered global-search panel, not a dropdown. Outside click and Escape dismiss it; ⌘F opens Find within the current chat. The earlier wordmark-adjacent search request is superseded. |
| Titlebar navigation | One compact original-size sidebar toggle, followed immediately by Back within the sidebar titlebar area. Match their optical stroke weight; the latest correction permits a slightly heavier ⌘B glyph. No duplicate toggle, forward button, or permanent button background. |
| Tools and paths | Tools, skill discovery, file access, writes, and command execution available by default within macOS permissions; optional restrictions in Settings. No project selection prerequisite. |
| Controls | Prefer common custom buttons, menus, dropdowns, and segmented controls. Action icons stay monochrome. Enabled parameters and selected toggles use blue highlights. |
| Composer | Model selection belongs in the composer. Welcome composer sits immediately below “How can I help?”. Add only a faint 1px border. |
| Validation | Repeated build → actual interaction → inspection → correction cycles. Maintain an itemized ledger; do not claim an infinite unattended run or mark untested items complete. |
| Current priority | Speed, responsiveness, and usability come first. Compare the fast older Bedrock Validation with the latest changes using identical workloads, fix measured regressions, and put the verified updates back into Bedrock Validation. Do not call a successful build the final result. |

## Scope and source comparison

- [ ] S01 Read the Pilot/Foxl source and identify every convenience feature within the final local scope.
- [x] S02 Record each missing feature separately in the Foxl convenience checklist.
- [x] S03 Record every settings control separately, including exclusions and native equivalents.
- [x] S04 Keep application implementation in Swift with native macOS interaction and compatibility fallbacks.
- [x] S05 Store conversations, drafts, skills, schedules, attachments, and preferences locally.
- [x] S06 Connect directly to the configured AWS region/profile or supported Bedrock API endpoint.
- [x] S07 Exclude Notes, cloud account/sync/relay/billing, shared projects, and organization features.
- [x] S08 Remove Files from the sidebar while retaining composer attachments and direct tool access.
- [x] S09 Remove the project concept from chat, tools, demo prompts, and user-facing help.
- [ ] S10 Preserve Demo library and keep it functional.
- [ ] S11 Preserve Automations and keep them functional.
- [ ] S12 Preserve Activity and keep it functional.
- [x] S13 Keep Skills management in Settings.
- [x] S14 Combine Archive and Trash under Settings.

## Main window and design system

- [ ] U01 Use one consistent spacing, radius, typography, icon, and control-size system.
- [ ] U02 Keep the main conversation screen clean, with minimal controls.
- [ ] U03 Support Light, Dark, and System without forcing black.
- [ ] U04 Keep Light surfaces near white, with restrained gray only where useful.
- [ ] U05 Retain a clean black Dark theme without inconsistent blue-gray panels.
- [ ] U06 Extend the frosted sidebar vertically through the titlebar to the bottom in both themes.
- [ ] U07 Extend the Settings sidebar through its titlebar in the same way.
- [ ] U08 Keep the sidebar divider straight and full height.
- [ ] U09 Set an attractive initial main-window size.
- [ ] U10 Start the sidebar expanded at a usable default width.
- [ ] U11 Enforce a minimum sidebar width so “Bedrock”, navigation titles, profile, and region do not wrap.
- [ ] U12 Preserve a user-resized valid sidebar width between launches.
- [ ] U13 Normalize Bedrock wordmark position, typography, and surrounding padding.
- [ ] U14 Remove the in-app Bedrock pictogram from the sidebar and main screen.
- [ ] U15 Improve chat-title leading padding and preserve single-line truncation.
- [x] U16 Keep one New chat button in main-window navigation.
- [x] U17 Keep one Settings entry in main-window navigation.
- [x] U18 Keep one sidebar toggle; remove the duplicate automatic/custom button.
- [x] U19 Keep the sidebar toggle's compact original size and match its optical stroke weight to Back; the latest user correction permits increasing the ⌘B glyph weight.
- [x] U20 Put Back immediately to the right of the toggle in the sidebar titlebar area.
- [x] U21 Remove permanent background shading from titlebar navigation buttons.
- [ ] U22 Animate sidebar opening/closing with the same behavior for click and ⌘B.
- [ ] U23 Respect Reduce Motion during sidebar and control transitions.
- [ ] U24 Make disabled Back visibly inactive and skip unavailable history entries.
- [x] U25 Restore Search to its original upper-right location and size.
- [x] U26 Remove duplicate search affordances in the sidebar and chat toolbar.
- [ ] U27 Keep icons monochrome with sufficient contrast in both themes.
- [ ] U28 Use consistent readable New chat, attachment, microphone, options, and settings icons.
- [ ] U29 Keep every circular button truly square before applying the circle shape.
- [ ] U30 Give Send a consistent enabled/disabled appearance in both themes.
- [x] U31 Remove redundant chevrons beneath ellipsis buttons.
- [ ] U32 Consolidate response parameters, image mode, plus, ellipsis, and settings controls.
- [ ] U33 Keep system-prompt title and chevron close together.
- [ ] U34 Normalize search-field backgrounds, borders, height, and focus treatment.
- [ ] U35 Make sidebar scrollbars thin and unobtrusive.
- [ ] U36 Remove the opaque transcript scrollbar track.
- [ ] U37 Center the welcome heading and composer as a single group.
- [ ] U38 Add a faint 1px composer border in both themes without a heavy outline.
- [ ] U39 Refine composer padding, input font, placeholder contrast, and button alignment.
- [x] U40 Review Apple’s current macOS/Liquid Glass guidance and use supported APIs with fallbacks.
- [ ] U41 Compare actual rendered UI with the supplied Codex references at narrow and normal widths.
- [ ] U42 Validate all menus and buttons through actual interaction, not screenshots alone.

## Search, navigation, and shortcuts

- [x] N01 Clicking Search opens a centered global conversation/command search panel by default, not a toolbar dropdown.
- [x] N02 Clicking outside global search dismisses it.
- [x] N03 Escape dismisses global search without deleting a draft.
- [x] N04 ⌘K opens the same global search.
- [x] N05 ⌘F opens only the current conversation's Find bar.
- [x] N06 Global results include actual matching content and navigate to the relevant passage.
- [x] N07 Global search handles old and new conversation formats.
- [x] N08 Find searches the full history even when only a recent page is rendered.
- [ ] N09 Search is cancelable and stale results never replace a newer query.
- [x] N10 ⌘N matches released behavior: create a distinct chat using the current model.
- [x] N11 ⌘D matches released behavior while keeping deletion recoverable in Trash.
- [x] N12 ⌘B matches the visible sidebar toggle.
- [x] N13 ⌘, opens Settings reliably from applicable windows.
- [x] N14 Back and ⌘[ restore the previous valid destination without losing drafts.
- [ ] N15 Preserve existing shortcut behavior with sheets, popovers, text selection, and IME.
- [x] N16 The centered search panel takes keyboard focus; typing must not edit the composer underneath.
- [ ] N17 Search and dropdown results support keyboard navigation, Return, and Escape.

## Chat, rendering, and attachments

- [ ] C01 Keep assistant model headings out of every transcript segment.
- [ ] C02 Make the actual response model/timestamp available through message details.
- [ ] C03 Stream text without repeated whole-history parsing or layout.
- [x] C04 Render Markdown headings, paragraphs, emphasis, links, quotes, lists, tables, and code.
- [x] C05 Preserve continuous selection across paragraphs and multiple list items.
- [x] C06 Draw list markers outside selectable text, like HTML list markers.
- [ ] C07 Use shallow rounded inline-code backgrounds around glyphs, without broad gray bands.
- [x] C08 Preserve exact source Markdown through Copy response.
- [x] C09 Preserve exact code and whitespace through code-copy actions.
- [x] C10 Sanitize right-click menus on selected assistant text to relevant copy/select actions.
- [x] C11 Keep composer context-menu editing actions useful without unrelated system services.
- [x] C12 Bound and sanitize HTML parsing and rendering.
- [x] C13 Handle lengthy pasted text without freezing or dropping the end of the input.
- [x] C14 Handle multiple pasted images without blocking the main thread.
- [x] C15 Handle mixed image/text/browser clipboard contents without duplicates or lost data.
- [ ] C16 Provide manageable attachment chips, previews, removal, and Remove all.
- [x] C17 Allow pasted-text attachments to be inspected and edited before sending.
- [x] C18 Preserve stable attachment identities and exact text through edits and retries.
- [x] C19 Preserve unsent text and attachment drafts through chat/model switches.
- [x] C20 Restore welcome-composer drafts and attachments after quit/relaunch.
- [x] C21 Restore ordinary-chat drafts and attachments after quit/relaunch.
- [ ] C22 Keep attachment import cancelable and show actionable errors without consuming the draft.
- [x] C23 Validate attachment capability/count/size limits before inference.
- [ ] C24 Edit, retry, and branch messages without losing original recoverable history.
- [x] C25 Add Foxl-style compact message queueing while a response runs.
- [x] C26 Queue text, attachments, skill context, and the intended model together.
- [x] C27 Inspect/edit/remove queued items.
- [x] C28 Interrupt and send a queued item without overlapping requests.
- [x] C29 Pause/recover the queue after cancellation or failure.
- [x] C30 Restore the queue after relaunch without silently starting paid requests.
- [x] C31 Preserve the current unsent draft when queued work begins.
- [x] C32 Keep long-history loading fast with a bounded rendered viewport.
- [ ] C33 Keep scroll anchors stable during streaming, resizing, and loading older/newer pages.
- [ ] C34 Remove scroll flicker, jumping, and unexpected auto-scroll while reading.
- [x] C35 Preserve prior per-thread scroll position when returning to a conversation.
- [ ] C36 Keep message/tool details searchable and copyable without blocking the transcript.
- [ ] C37 Make truncation, stop reason, and context reduction understandable without toolbar clutter.
- [x] C38 Fix hangs when clicking generated images; repeatedly open, zoom, copy, save, and close large-image previews.
- [x] C39 Accept common UTF-8 source/configuration files through Attach files, preserve their exact bytes, and send them using a supported document format. Swift attachment → skill discovery/load → actual Nova response passed on 71.

## Models, inference, and demos

- [ ] M01 Support the supplied active model families through a maintained catalog.
- [x] M02 Exclude legacy models from new choices while keeping old conversations readable.
- [ ] M03 Refresh models and inference profiles from the actual AWS connection.
- [ ] M04 Prefer valid direct/profile/Mantle routes; do not invent regional availability.
- [x] M05 Keep model IDs immutable and integrate selection with Default model settings.
- [x] M06 Make GPT-6 Astra selectable as default and inside a conversation.
- [x] M07 Preserve context when switching models in an existing conversation.
- [x] M08 Preserve draft text and attachments during a model switch.
- [x] M09 Preserve valid tool call/result pairs across provider switches.
- [ ] M10 Apply model-specific reasoning and parameter capabilities correctly.
- [x] M11 Keep the model selector in the composer with a consistent compact design.
- [x] M12 Remove unnecessary “All providers” controls from the composer model selector.
- [ ] M13 Search model names/IDs and make favorites practical.
- [ ] M14 Handle long model names and narrow windows without clipping controls.
- [ ] M15 Distinguish text/image/video/speech/embedding/rerank capabilities and valid invocation APIs.
- [ ] M16 Verify every Demo library preset chooses a compatible model.
- [x] M17 Fix image-generation demos that accidentally select an upscaler/editor.
- [x] M18 Fix profile-required image invocation and show a concise actionable error.
- [ ] M19 Preserve demo variables, system prompts, and skills in the resulting chat.
- [ ] M20 Validate comparison, embeddings, and other retained demo paths.
- [x] M21 Keep AWS errors readable with raw details available on demand.
- [ ] M22 Measure actual request timing/token throughput rather than claiming unmeasured performance superiority.

## Local tools, skills, MCP, and automation

- [x] T01 Advertise the actual available tools to the selected model.
- [x] T02 Provide command execution, not just file read/list/search/Git tools.
- [x] T03 Discover, list, and load the actual installed skills by English identifier.
- [x] T04 Make automatic skill loading work without manually selecting a project.
- [x] T05 Validate skill invocation through a real Bedrock response.
- [x] T06 Validate command execution through a real Bedrock tool loop.
- [x] T07 Make local path access permissive by default within OS permissions.
- [x] T08 Offer configurable path and per-tool restrictions in Settings.
- [x] T09 Enforce the optional file allowlist for built-in file reads, traversal, symlinks, and writes. Command execution has separate enablement, approval, timeout, and cancellation controls; it is not sandboxed by the file allowlist.
- [ ] T10 Show tool name, status, duration, input, full output, and error details.
- [ ] T11 Open, reveal, and copy paths from file-producing tool results.
- [ ] T12 Keep long tool output searchable and copyable.
- [x] T13 Support real local MCP stdio transport with arguments and environment.
- [ ] T14 Support MCP HTTP configuration with headers and actionable errors.
- [ ] T15 List, inspect, enable, and disable individual MCP tools.
- [x] T16 Preserve nested schemas and disambiguate duplicate tool names.
- [ ] T17 Import/export MCP configuration safely with previews.
- [x] T18 Reconnect one MCP server without disrupting healthy servers or chats.
- [x] T19 Cancel/timeout failed MCP calls without leaving a run stuck.
- [ ] T20 Preserve text, structured, resource, and image tool results.
- [ ] T21 Import, export, create, edit, enable, and reload skills from Settings.
- [ ] T22 Show malformed-skill/prerequisite diagnostics and inspect bundled references.
- [ ] T23 Return from “Use in chat” to the correct composer with its draft intact.
- [ ] T24 Implement the additional in-scope Foxl tool conveniences listed individually in the Foxl audit.
- [ ] T25 Validate creating/editing/duplicating/running/stopping local automations.
- [ ] T26 Validate scheduling, timezone, missed runs, restart, and non-overlap behavior.
- [ ] T27 Validate Activity filters, run details, usage, original errors, and conversation links.
- [ ] T28 Keep credentials and configured secrets out of exports and diagnostic logs.

## Settings and compatibility

- [ ] G01 Validate every General control and its persistence.
- [ ] G02 Validate every Appearance control in Light/Dark/System.
- [ ] G03 Validate AWS region, profile, refresh, API-key Save, Test connection, and Advanced fields.
- [ ] G04 Validate Default model, model favorites, model visibility, and model-specific controls.
- [ ] G05 Validate every Skills control and sheet.
- [ ] G06 Validate every Tools & MCP control and sheet.
- [ ] G07 Validate Keyboard reference and supported rebinding/conflict handling.
- [ ] G08 Validate combined Archive/Trash search, restore, batch actions, and permanent-delete confirmation.
- [ ] G09 Validate Data/history import/export, storage location, and migration.
- [ ] G10 Validate every Advanced control.
- [ ] G11 Fix clipped inputs, overlapping controls, malformed rows, and excessive gaps at minimum width.
- [ ] G12 Replace inconsistent native popup controls with the common custom dropdown where appropriate.
- [ ] G13 Use blue enabled-state highlighting for custom parameters and switches.
- [x] G14 Preserve old preference keys, per-model values, and default model migration.
- [x] G15 Preserve legacy chat formats, attachments, tools, titles, and timestamps.
- [ ] G16 Keep existing bundle identity, keychain access, and original data location compatibility.
- [x] G17 Keep data migration atomic/recoverable and do not overwrite unreadable history with empty data.
- [ ] G18 Preserve Quick Access, menu-bar access, launch-at-login, notifications, and updates.
- [ ] G19 Respect accessibility contrast, transparency, font size, keyboard navigation, and IME.

## Performance, validation, dependencies, and delivery

- [x] V01 Reproduce and fix “Application not responding” during chat loading and scrolling.
- [x] V02 Reproduce and fix hangs from long text, HTML, and multiple pasted images.
- [x] V03 Measure long-chat first display, scrolling/resizing, and large-paste responsiveness.
- [ ] V04 Remove synchronous heavy parsing, file reads, and repeated layout from the main thread.
- [ ] V05 Use bounded caches, cancelable tasks, and correct session lifecycle cleanup.
- [x] V05a Keep image decoding, encoding, file-size calculation, and preview layout out of repeated main-thread body evaluation.
- [x] V06 Update all direct dependencies to current stable compatible releases.
- [x] V07 Resolve and validate transitive dependency changes.
- [x] V08 Update bundled rendering assets and preserve their licenses/provenance.
- [x] V09 Add meaningful core, integration, renderer, clipboard, migration, and performance regressions.
- [x] V10 Add deterministic local MCP fixtures and real transport tests.
- [ ] V11 Add UI tests for navigation, search dismissal, settings, model selection, queueing, and shortcuts. Eleven native UI scenarios are implemented and type-check; a dedicated UI queue scenario and hosted execution remain.
- [x] V12 Run the relevant local suites and document precise pass/skip/failure counts.
- [x] V13 Configure PR CI for build/tests and gate release packaging on validation. Workflow syntax passes; hosted execution is tracked separately.
- [x] V14 Separate offline CI fixtures from optional paid/live-provider tests.
- [ ] V15 Actually run the latest app and inspect Light/Dark/System and narrow/normal layouts.
- [ ] V16 Verify the final app with real menus, search, settings, tools, and representative model calls.
- [ ] V17 Repeat targeted validation after fixes; retain evidence for each checked requirement.
- [x] V18 Relaunch the updated app with existing conversations and drafts preserved.
- [ ] V19 Rebuild and exercise the complete scenario matrix in the updated Bedrock Validation app, including sidebar, icon, search, and image-preview corrections. The earlier Performance-app request is superseded by the latest Validation request.
- [x] V20 Reproduce the newer build's typing/scroll regression against the older Validation app and fix the application-scene invalidation loop. See [PERFORMANCE.md](PERFORMANCE.md).
- [x] V21 Recheck the latest Validation binary after accessibility corrections and preserve the existing data, shortcuts, and responsiveness.
- [x] R01 Reorganize source, tests, resources, and configuration into a standard public Swift repository.
- [ ] R02 Remove unused legacy screens, duplicate resources, dead helpers, and stale project entries.
- [ ] R03 Preserve Xcode targets, schemes, build configuration, resource membership, and app identity.
- [x] R04 Verify every registered source/resource path and detect duplicate compilation entries.
- [ ] R05 Refresh README to the quality and clarity of the referenced Foxl repository.
- [ ] R06 Capture new Light/Dark screenshots from the actual finished app with dedicated demo data.
- [ ] R07 Capture an animated main demonstration of actual interaction with a static fallback.
- [ ] R08 Replace stale README media and document reproducible capture.
- [ ] R09 Document verified setup, model support, shortcuts, tools, skills, MCP, privacy, and local storage.
- [ ] R10 Update contributor/build/test/troubleshooting instructions for the final structure.
- [ ] R11 Record every remaining limitation honestly; never check items merely because work stopped.

## Latest validation gate

The current priority is the updated **Bedrock Validation** app, preserving its
existing identity and data. Release 64 includes the recent UI and performance
fixes and has been exercised with actual input, scrolling, shortcuts, model
switching, attachment restart, generated-image preview, and real inference.
Its app integration suite ran 64 cases: 60 passed and four opt-in network
cases skipped. The older-page reading-position regression found during this
pass remains open. Evidence and exact limits are recorded in
[PILOT_VALIDATION.md](PILOT_VALIDATION.md) and
[PERFORMANCE_VALIDATION_MATRIX.md](PERFORMANCE_VALIDATION_MATRIX.md).
