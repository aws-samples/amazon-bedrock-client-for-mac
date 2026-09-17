# User requirements and completion ledger

Last updated: 2026-09-17. This is the authoritative checklist for the requested rebuild. Each checkbox requires both implementation and relevant verification; a code path, screenshot, or passing build alone is not proof that a feature works. The detailed Foxl audit is in [Foxl convenience audit](foxl-parity.md), every source settings row is mapped in [foxl-settings.md](foxl-settings.md), and measured evidence belongs in [validation-log.md](validation-log.md).

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
| Conversation history | Open the full conversation as one continuous scrollable transcript. Remove manual “Load earlier/newer messages” controls and page limits. Keep long-history rendering responsive without making the user load pages. |
| Validation | Repeated build → actual interaction → inspection → correction cycles. Maintain an itemized ledger; do not claim an infinite unattended run or mark untested items complete. |
| Current priority | Speed, responsiveness, and usability come first. Compare the fast older Bedrock Validation with the latest changes using identical workloads, fix measured regressions, and put the verified updates back into Bedrock Validation. Do not call a successful build the final result. |
| Release gate | Latest instruction: run changed or previously failing scenarios locally, then require the final main revision and release workflow to pass the complete GitHub CI. A redundant full local rerun is not required. |
| Repository | Organize Swift sources by responsibility, use descriptive filenames, remove verified dead files/resources, and update the Xcode project, scripts and documentation together. Preserve stored data and production identity. |

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
- [x] U03 Support Light, Dark, and System without forcing black. (Light/Dark/System were exercised locally and by the hosted Settings test.)
- [x] U04 Keep Light surfaces near white, with restrained gray only where useful. (Latest Light main/Settings captures were inspected; see [Media](../media.md).)
- [x] U05 Retain a clean black Dark theme without inconsistent blue-gray panels. (Latest Dark main/Settings captures were inspected; see [Media](../media.md).)
- [x] U06 Extend the frosted sidebar vertically through the titlebar to the bottom in both themes. (The actual Light/Dark captures show a full-height sidebar; see [Media](../media.md).)
- [x] U07 Extend the Settings sidebar through its titlebar in the same way. (Settings lifecycle/appearance checks and actual full-height captures passed; see validation-log.md.)
- [x] U08 Keep the sidebar divider straight and full height. (The latest actual Light/Dark captures retain the straight full-height divider.)
- [x] U09 Set an attractive initial main-window size. (The full UI suite verifies the initial width against the available display.)
- [x] U10 Start the sidebar expanded at a usable default width. (The titlebar UI case verifies an expanded sidebar with at least a 200-point New chat target.)
- [ ] U11 Enforce a minimum sidebar width so “Bedrock”, navigation titles, profile, and region do not wrap.
- [ ] U12 Preserve a user-resized valid sidebar width between launches.
- [x] U13 Normalize Bedrock wordmark position, typography, and surrounding padding. (Latest actual main-window captures show the wordmark inset and single-line label.)
- [x] U14 Remove the in-app Bedrock pictogram from the sidebar and main screen. (Latest actual main-window and Settings captures contain no Bedrock pictogram.)
- [x] U15 Improve chat-title leading padding and preserve single-line truncation. (The latest main-window captures retain inset, single-line chat titles.)
- [x] U16 Keep one New chat button in main-window navigation.
- [x] U17 Keep one Settings entry in main-window navigation.
- [x] U18 Keep one sidebar toggle; remove the duplicate automatic/custom button.
- [x] U19 Keep the sidebar toggle's compact original size and match its optical stroke weight to Back; the latest user correction permits increasing the ⌘B glyph weight.
- [x] U20 Put Back immediately to the right of the toggle in the sidebar titlebar area.
- [x] U21 Remove permanent background shading from titlebar navigation buttons.
- [ ] U22 Animate sidebar opening/closing with the same behavior for click and ⌘B.
- [ ] U23 Respect Reduce Motion during sidebar and control transitions.
- [x] U24 Make disabled Back visibly inactive and skip unavailable history entries. (Navigation core tests and actual toolbar checks cover disabled Back and deleted entries.)
- [x] U25 Restore Search to its original upper-right location and size.
- [x] U26 Remove duplicate search affordances in the sidebar and chat toolbar.
- [ ] U27 Keep icons monochrome with sufficient contrast in both themes.
- [ ] U28 Use consistent readable New chat, attachment, microphone, options, and settings icons.
- [ ] U29 Keep every circular button truly square before applying the circle shape.
- [ ] U30 Give Send a consistent enabled/disabled appearance in both themes.
- [x] U31 Remove redundant chevrons beneath ellipsis buttons.
- [ ] U32 Consolidate response parameters, image mode, plus, ellipsis, and settings controls.
- [x] U33 Keep system-prompt title and chevron close together. (The actual Models Settings capture shows the compact Default/chevron control.)
- [ ] U34 Normalize search-field backgrounds, borders, height, and focus treatment.
- [x] U35 Make sidebar scrollbars thin and unobtrusive. (Actual sidebar wheel/thumb/keyboard checks passed; see the WS04–WS06 evidence in [the original port checklist](port-checklist.md).)
- [x] U36 Remove the opaque transcript scrollbar track. (Latest Dark transcript capture shows the clear track and slim thumb.)
- [x] U37 Center the welcome heading and composer as a single group. (Actual welcome draft/relaunch and native layout checks passed; see validation-log.md.)
- [x] U38 Add a faint 1px composer border in both themes without a heavy outline. (Latest actual Light/Dark composer captures were inspected.)
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
- [x] N08 Find searches the full history, including messages outside the current screen.
- [x] N09 Search is cancelable and stale results never replace a newer query. (ConversationSearch tests cover cancellation/cache replacement; the palette also checks the current query before publishing.)
- [x] N10 ⌘N matches released behavior: create a distinct chat using the current model.
- [x] N11 ⌘D matches released behavior while keeping deletion recoverable in Trash.
- [x] N12 ⌘B matches the visible sidebar toggle.
- [x] N13 ⌘, opens Settings reliably from applicable windows.
- [x] N14 Back and ⌘[ restore the previous valid destination without losing drafts.
- [ ] N15 Preserve existing shortcut behavior with sheets, popovers, text selection, and IME.
- [x] N16 The centered search panel takes keyboard focus; typing must not edit the composer underneath.
- [ ] N17 Search and dropdown results support keyboard navigation, Return, and Escape.

## Chat, rendering, and attachments

- [x] C41 Remove all manual earlier/newer-message buttons. The full transcript is scrollable immediately; offscreen rendering loads automatically, including after sending a new message. (Complete 1,000-message scrolling/search/navigation and stream-completion UI scenarios each passed three times; the full-pipeline gate is D09.)
- [x] C42 Show a compact model-switch divider at the transition, preserve it after reopening the chat, and keep it out of inference history. (The full UI test verifies one divider after New chat → Back, exactly two SDK requests, and no divider text in request context.)
- [ ] C43 Tighten the vertical gap between an answer and its Copy/Retry/More actions, including text, code, tables, and generated images.
- [x] C44 Copy selected rendered text as semantic HTML with bold, italic, lists, links, and tables; preserve plain-text fallback and keep Copy response as original Markdown.

- [x] C01 Keep assistant model headings out of every transcript segment. (Actual tool-loop and response captures have no repeated assistant model headings.)
- [ ] C02 Make the actual response model/timestamp available through message details.
- [ ] C03 Stream text without repeated whole-history parsing or layout.
- [x] C04 Render Markdown headings, paragraphs, emphasis, links, quotes, lists, tables, and code.
- [x] C05 Preserve continuous selection across paragraphs and multiple list items.
- [x] C06 Draw list markers outside selectable text, like HTML list markers.
- [x] C07 Use shallow rounded inline-code backgrounds around glyphs, without broad gray bands. (Native rounded-glyph decorations and actual selection/rendering checks are recorded in the Foxl UX12 evidence.)
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
- [ ] C32 Keep long-history loading fast while making the complete conversation immediately scrollable.
- [ ] C33 Keep scroll anchors stable during streaming, resizing, and moving through the full conversation.
- [ ] C34 Remove scroll flicker, jumping, and unexpected auto-scroll while reading.
- [x] C35 Preserve prior per-thread scroll position when returning to a conversation.
- [ ] C36 Keep message/tool details searchable and copyable without blocking the transcript.
- [ ] C37 Make truncation, stop reason, and context reduction understandable without toolbar clutter.
- [x] C38 Fix hangs when clicking generated images; repeatedly open, zoom, copy, save, and close large-image previews.
- [x] C39 Accept common UTF-8 source/configuration files through Attach files, preserve their exact bytes, and send them using a supported document format. Swift attachment → skill discovery/load → actual Nova response passed on 71.
- [ ] C40 Keep transparency checkerboards within image bounds, and avoid labeling generated JPEGs as PNGs in the preview.

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
- [x] M24 Reuse the conversation model selector in Automations: one row per model, visible provider, searchable IDs and explicit inference-route choices. Preserve an existing schedule's exact model ID until the user changes it. (The optimized UI case passed grouping, provider identity, selection, save, relaunch and editing without changing the saved route.)
- [x] M23 Hide Nova 2 Pro Preview from available model choices, including cached/live discovery, profiles, favorites, and the default-model picker. Keep the existing recording unchanged. (Core regression covers ACTIVE metadata, restored cache entries, regional/application profiles and favorites. The rebuilt app excludes it in both pickers; the refreshed 180-entry cache contains no preview entries, and an old preview default falls back to an available model.)

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
- [x] T10 Show tool name, status, duration, input, full output, and error details. (Actual tool disclosure and original Input/Output details were inspected; see validation-log.md.)
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
- [x] G20 Show one Reset button for Quick Access shortcut in Settings → Keyboard. Restore ⌥Space, end shortcut recording when resetting, and retain reset access when Quick Access is off. (Release build and actual Settings UI verified: one Reset, custom ⌃⌥K restored to ⌥Space while disabled, recording ends on Reset, and reopening Settings preserves the default. UI regression assertion added.)

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
- [x] V11 Add UI tests for navigation, search dismissal, settings, model selection, queueing, and shortcuts. All 26 scenarios passed in complete local CI on `765e40e`; hosted delivery remains tracked under D04/D06.
- [x] V12 Run the relevant local suites and document precise pass/skip/failure counts.
- [x] V13 Configure PR CI for build/tests and gate release packaging on validation. Workflow syntax passes; hosted execution is tracked separately.
- [x] V14 Separate offline CI fixtures from optional paid/live-provider tests.
- [ ] V15 Actually run the latest app and inspect Light/Dark/System and narrow/normal layouts.
- [ ] V16 Verify the final app with real menus, search, settings, tools, and representative model calls.
- [x] V17 Repeat targeted validation after fixes; retain evidence for each checked requirement. (Repeated viewport tests, complete local CI, and the Settings follow-up are recorded in validation-log.md.)
- [x] V18 Relaunch the updated app with existing conversations and drafts preserved.
- [ ] V19 Rebuild and exercise the complete scenario matrix in the updated Bedrock Validation app, including sidebar, icon, search, and image-preview corrections. The earlier Performance-app request is superseded by the latest Validation request.
- [x] V20 Reproduce the newer build's typing/scroll regression against the older Validation app and fix the application-scene invalidation loop. See [performance.md](../performance.md).
- [x] V21 Recheck the latest Validation binary after accessibility corrections and preserve the existing data, shortcuts, and responsiveness.
- [x] V22 Keep the normal Bedrock Validation app separate from offline UI tests. The normal Release completed a real Nova skill-discovery request. A distinctly named UI test app uses fake credentials and an exact loopback endpoint; real SDK failure/recovery and Quick Access requests passed. Core/native isolation tests cover invalid ports, other inference routes, credential resolution, and profile paths. See validation-log.md.
- [x] R01 Reorganize source, tests, resources, and configuration into a standard public Swift repository.
- [ ] R02 Remove unused legacy screens, duplicate resources, dead helpers, and stale project entries.
- [x] R02a Remove the unreferenced Vapor product and its seven unused package-graph entries; reject unused directly linked products during CI source validation.
- [x] R03 Preserve Xcode targets, schemes, build configuration, resource membership, and app identity. (Project validation and the complete optimized core/native/UI build pass.)
- [x] R04 Verify every registered source/resource path and detect duplicate compilation entries.
- [x] R05 Refresh README to the quality and clarity of the referenced Foxl repository.
- [x] R06 Capture new Light/Dark screenshots from the actual updated app with dedicated demo data.
- [x] R07 Capture an animated main demonstration of actual interaction with a static fallback.
- [x] R08 Replace stale README media and document reproducible capture.
- [x] R09 Document verified setup, model support, shortcuts, tools, skills, MCP, privacy, and local storage.
- [x] R10 Update contributor/build/test/troubleshooting instructions for the final structure.
- [x] R11 Record every remaining limitation honestly; never check items merely because work stopped. (The completion audit retains the actual implementation gaps and unverified controls.)
- [x] R12 Replace the low-resolution README animation/video with native-resolution captures; clean the rounded window's outer edges, keep consistent framing and visually inspect the final README media. (September 16 exports preserve the 2480×1560 native window inside a 2608×1688 frame. The 35-second WebP/MP4, Light/Dark captures, GitHub-sanitized README layout, media hashes, and links were inspected; see [media.md](../media.md).)
- [x] R13 Make the main demonstration visually engaging: develop a concept with a text model, switch to an image model in the same conversation, generate a real image, and open the result. Do not use clicking List skills as the main demonstration. (The real Nova → Stable Image Ultra conversation, complete 9.22-second image request, preview zoom/Fit/close interactions, and final exported frames were verified.)
- [x] R14 Re-record the same concept-to-image demonstration in the current Release app using GPT-6 Astra with Low reasoning effort, then Stable Image Ultra 1.0. Replace the README animation, movie, and matching screenshots, retain actual inference timing, and verify the exported media. (Real AWS conversation, Low effort setting, image generation, preview, zoom, and fit verified. Refreshed 35-second Retina media preserves the 8.99-second image request; MP4 frames and animated WebP inspected. GitHub-rendered README has no horizontal overflow, and the updated downloads and media. Documentation/media validation passes.)

- [x] R15 Remove all five README header badges (macOS, Swift, Release, Validation, License), retaining the prominent latest-DMG download button. Supersedes the earlier badge-centering request.

The September 16 evidence audit and unresolved implementation gaps are recorded in [todo-audit.md](todo-audit.md).

## Latest validation gate

The current priority is the updated **Bedrock Validation** app, preserving its
existing identity and data. The current optimized app includes the recent UI and performance
fixes and has been exercised with actual input, scrolling, shortcuts, model
switching, attachment restart, generated-image preview, and real inference.
Targeted optimized native and UI tests now exercise continuous history, stream
completion, model switching, rich clipboard data, tool details, and the shared
automation model selector. The full local/hosted release gate remains separate
from those targeted passes. The old earlier/newer-page implementation is
superseded by a complete lazy transcript. Exact run results, performance limits,
and remaining features are recorded in [the completion audit](todo-audit.md),
[validation-log.md](validation-log.md) and [the validation matrix](validation-matrix.md).


## GitHub delivery and version 2.0.0

- [x] D01 Run the regression workflow on every main push, release-branch push and pull request.
- [x] D02 Gate release packaging and publication on the same optimized-app validation workflow.
- [x] D03 Exercise streaming, model switching, tools and queues through the real AWS SDK against an isolated loopback protocol fixture. All 26 local UI scenarios passed on `765e40e`, including stream reading-position preservation and error recovery.
- [ ] D04 Execute the complete native/UI workflow on GitHub, fix failures and retain logs, screenshots, measurements and request evidence.
- [x] D05 Replace README screenshots and the animated demonstration with fresh actual-app captures; publish an MP4 and static fallback.
- [ ] D06 Validate and push the final revision to main, then confirm its workflow succeeds.
- [ ] D07 Tag v2.0.0; build universal Intel/Apple silicon binaries, sign, notarize, staple and publish on GitHub.
- [ ] D08 Verify the published DMG checksum, release assets, release notes and Homebrew update.
- [x] D09 Follow the latest release-validation instruction: run changed or previously failing scenarios locally and retain their evidence; require complete main CI before tagging. Native viewport cases and affected UI scenarios passed repeated targeted runs. The redundant full local rerun was canceled at the user's request; it is not a passing full-CI receipt.
- [ ] D10 Verify the reorganized `Bedrock.xcodeproj`, `Bedrock` scheme, `BedrockCore` package, feature directories and resource names in local and hosted builds; retain the production bundle identifier, data paths and Core Data schema.
