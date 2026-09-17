# Local port validation

This file records executed checks. The acceptance inventory is
[requirements.md](requirements.md); [the completion audit](todo-audit.md) separates
verified behavior, remaining implementation gaps and release gates.

## September 17, 2026

- Small-window tool inspection revealed a separate nested-scrolling problem:
  wheel input over a short native input preview stayed inside that preview,
  leaving Open details below the conversation viewport. Actual wheel input
  outside the preview scrolled normally and canceled position preservation.
  Inline previews now forward wheel input to the conversation when their full
  content fits; long output panes and detail sheets retain native scrolling.
  The UI scenarios scroll directly over the input preview before opening the
  original details. All three targeted UI scenarios passed three consecutive
  runs in `inline-preview-scroll-routing.xcresult`: expanded-tool model switches,
  small-window full-history navigation and skills/shell original details.
- The initial native wheel assertion ran before AppKit's next animation frame
  and failed despite successful UI scrolling. An isolated native reproduction
  measured zero immediate movement followed by the correct 80-point movement.
  The test now observes movement within a bounded deadline and matches the
  app's vertical-scroller configuration. `native-wheel-and-viewport-final.xcresult`
  passed all 15 viewport cases three times, including independent long-output
  scrolling, top-boundary intent, native insets and late clip compensation.
  These targeted results precede the complete local and hosted release gates.
- Hosted CI `35180323291` exposed another continuous-history defect on its
  1024×674 window. The recording shows question 0 appearing at the end of a
  thumb drag, followed by a jump to question 32 as lazy layout corrected the
  document. This disproves the earlier conclusion that extending the drag
  endpoint was sufficient. The viewport now retains an explicit top-boundary
  intent from the live gesture and observes later clip-offset adjustments,
  while a new user gesture cancels preservation immediately.
- The local `4f50cee` run was deliberately canceled after this hosted failure
  was inspected. All executed cases passed (115 core, 43 renderer, 102 native
  plus four optional skips, and 17 UI cases), but it is not a complete CI
  receipt. The full-history UI scenario now resizes to the small hosted window
  locally; native regressions reproduce offset compensation both before and
  after the end-of-scroll notification.
- The first boundary run passed 13 native viewport cases and the small-window
  history and stream-completion UI scenarios three times each, but exposed a
  40-point shift during tool inspection. A full-size-content window's native
  top boundary can be negative because of its titlebar inset. Restoration now
  uses AppKit's constrained bounds instead of zero; a dedicated native case
  checks preservation of that inset.
- Full local CI at `9fc1597` passed all non-UI suites and 26/27 UI scenarios.
  The skills/shell scenario exposed a different intermittent defect: after
  expanding a completed tool, automatic following moved its Open details button
  between coordinate resolution and the click. The recording shows the pointer
  landing below the moved control. Tool and reasoning inspection now cancels
  queued following and preserves the reading position before expansion.
  The regression also checks that the tool header does not move; it does not
  add a sleep or retry a missed click.
- `tool-inspection-position.xcresult` then passed both the real skills/shell
  details scenario and expanded-tool chat/image model-switch scenario three
  consecutive times each. The new header-position assertion passed in every
  repetition. A complete unchanged-source CI run remains the release gate.
- A normal, online Release build at `71a428c` reproduced a new hang after
  inspecting a completed shell tool and rapidly switching between Astra and
  Stable Image Ultra. Two main-thread samples show an unending SwiftUI
  animation/layout transaction; one run reached roughly 1.5 GB RSS. This was
  not an AWS timeout. Model selection now closes the picker before applying
  the new model in a transaction that does not animate transcript layout.
- The same public-Accessibility reproduction completed 12 rapid switches in
  the corrected normal Release build, preserving the expanded tool and composer.
  Afterward, an actual Stable Image Ultra request completed in about 10 seconds.
  Its image opened, zoomed, fitted and closed three times; switching back to
  Astra and sending a follow-up also completed without an SDK error. These
  are live account-specific checks, separate from the loopback tests. Private
  sidebar history in their screenshots is retained locally, not published.
- Hosted CI `35176696548` at `765e40e` passed the core, renderer and native app
  suites, and 25 of 26 UI cases. Its full-history thumb drag stopped just short
  of the first question on the runner's smaller display. The test now drags
  beyond the top of the native scroll slot instead of four points inside it;
  the requirement that the first question be visible remains unchanged.
- `model-switch-and-native-thumb.xcresult` passed both the expanded-tool model
  switch scenario and complete-history scroll/search/return scenario three
  times each. Inline tool previews subsequently moved to the existing native
  text view with bounded height and leading alignment; their exact text and
  placement are now asserted by the tool-details UI case. The final whole-suite
  run must include that presentation change.
- Full local CI at `92dd023` passed core 115, renderer/clipboard 43 and native
  app 102 cases (plus four optional network skips), with 26/27 UI cases passing.
  The new preview test incorrectly required `{}` rather than accepting the JSON
  encoder's whitespace. It now checks the parsed input and exact agreement
  between preview and detail text, retaining the output and alignment assertions.
  The corrected original-input/output UI scenario passed in
  `native-tool-preview-input.xcresult`; a new complete execution is still required.
- Complete local CI passed on clean revision `765e40e`: 115 portable core
  cases, 43 standalone renderer/clipboard cases, 105 app integration cases
  (101 passed and four opt-in public MCP diagnostics skipped), and all 26 UI
  scenarios. No required case failed or skipped, and the input hashes and
  executable permissions were unchanged throughout the run.
- The full run includes actual model-switch/reopen boundaries, original rich
  copy, generated-image zoom/copy/reopen, queues and restart, mixed attachments,
  tool execution, automation model persistence, and full-history navigation.
  Screenshots from Models, AWS connection and Dark appearance were inspected:
  the settings sidebar extends through the titlebar and the fields remain
  readable without the former clipped popup controls.
- A runtime warning in the otherwise passing Settings case was symbolicated to
  `PromptTemplateStore` rewriting an unchanged system prompt while Models was
  rendering. The store now avoids that write; default-model selection also
  avoids assigning through both its binding and its callback. A new regression
  checks unchanged preset initialization/reselection/reload and actual edited
  instructions. All six window/preset tests and the complete Settings UI case
  passed afterward, with no publishing-during-view-update warning.
- The actual optimized app's full 1,000-message transcript now uses a lazy scroll
  container. The former table accessibility proxies had instantiated offscreen
  hosting views and exhausted the main thread during inspection.
- A remaining search-position failure was reproduced: SwiftUI moved the target
  row by 1,104 points while its native view still reported the previous position.
  The viewport now uses measured content coordinates, retaining them while a
  pending target is briefly detached. User scrolling cancels restoration before
  lazy layout starts; navigation captures the position before teardown.
- `authoritative-layout-restoration.xcresult` passed all 11 native viewport
  regressions three times. Both actual UI scenarios passed three times each:
  first/last-message scrolling plus search and Activity → Back, and completion of
  a controlled response while reading an earlier passage. No manual history
  loading controls are used.
- The portable core wrapper passed 115 cases. Targeted app UI cases also passed
  automation model deduplication/provider/route persistence, skills and shell
  execution, exact tool details, rich HTML selection/source-Markdown copying,
  model context switching, Quick Access handoff and long-history typing.
- The new image/search/automation SDK loop passed: it checked the actual 64×48
  image bytes, found an earlier conversation's marker, and persisted a paused
  automation with its timezone and weekdays before locating its visible card.
- All 30 package versions and the six workflow action versions were rechecked.
  AWS SDK 1.7.85 and Smithy 0.252.0 are resolved; Crypto 4.5.2 remains the latest
  version compatible with the certificate dependency. See [dependencies](../dependencies.md).
- `full-ci-765e40e/ci-result.json` is a complete local receipt. The small Settings
  follow-up and subsequent model-switch correction must be included in the final
  unchanged-source local/hosted execution before tagging. GitHub Actions and
  Releases record subsequent execution.

Evidence is retained under
`/tmp/bedrock-pilot-validation/release-completion/`, including
`authoritative-layout-restoration.xcresult`, `validated-controls.xcresult`,
`complete-drag-and-tool-feedback.xcresult`, `full-ci-765e40e/Bedrock.xcresult`,
`prompt-initialization.xcresult`, `live-validation-71a428c`,
`live-reproduce-71a428c`, `rapid-switch-transaction-2`,
`model-switch-and-native-thumb.xcresult`,
`full-ci-92dd023/Bedrock.xcresult`, `native-tool-preview-input.xcresult`,
`full-ci-9fc1597/Bedrock.xcresult`, `tool-inspection-position.xcresult`,
the viewport diagnostic profiles, and
the raw performance measurements described in [Performance](../performance.md).

## September 16, 2026 — earlier checkpoint

The entries below this section preserve earlier experiments and build numbers;
they are not the current release status. The local UI-automation setup failure
described here was resolved before the September 17 executions above.

- The ordinary optimized Release app completed a real Nova 2 Lite request
  that listed the installed skills. The reported “AWS requests are disabled”
  message came from an offline test copy; preview launchers now distinguish
  **Bedrock Validation**, **Bedrock Showcase**, and **Bedrock UI Tests**.
  Offline test clients derive their exact loopback endpoint from the fixture,
  use a fake SDK credential resolver, and never fall back to AWS. CI removes
  inherited AWS environment variables.
- The latest portable core suite passed **98 cases**, zero failures.
  The latest optimized native suite executed **82 cases: 78 passed, four
  opt-in public-network diagnostics skipped, zero failures**. These include
  connection isolation, profile overrides, Quick Access lifecycle, IME input,
  image/clipboard work, and real local MCP transports.
- Hosted run **35116246289**, revision `6dea03a`, completed the core,
  standalone renderer, and native suites successfully. It ran all 23 UI
  scenarios: **20 passed and three failed**. The background-command tool loop
  and output-limit continuation both passed in the actual app.
- The remaining image failure was reproduced with real pointer clicks:
  a zoomed image intercepted the Fit button outside its visible viewport.
  Moving input gestures to the bounded viewport fixed three consecutive
  open → zoom → Fit → close cycles. This was a real input bug, not a timing
  assertion change.
- Quick Access exposed an AXWindow, while its UI test queried a dialog.
  Its delayed focus-loss callback could also close a newly reopened panel.
  The corrected native lifecycle test and actual Escape → reopen → submit
  sequence passed; the request reached the local Bedrock protocol fixture.
- Failure recovery exposed selectable error text through AXValue rather
  than AXLabel. The test now uses its stable identifier and checks the actual
  message. The protocol fixture also incorrectly rejected a new message when
  Converse retained the prior failed prompt in consecutive-user context.
  After that fixture correction, the real SDK/app displayed the failure and
  completed the next request. All **four protocol-fixture tests** passed.
- Full local XCTest UI execution still requires macOS UI-automation
  authentication. Targeted native and independent pointer/keyboard checks
  are evidence for the fixes, not a replacement for the required complete
  local CI run. No v2.0.0 release or main-branch push has been made.

Evidence under `/tmp/bedrock-pilot-validation/`:
`release-preflight/isolation-core-fixed`,
`release-preflight/native-interactions-fixed`,
`release-preflight/normal-release-fixed`,
`release-preflight/normal-release-interactions`,
`release-preflight/github-35116246289`,
`ui-review-interactions`, and `ui-review-recovery`.

## Investigation environment

- Source app: `/Users/sanghwa/workspaces/foxl-ai/pilot`.
- Target: Swift/SwiftUI macOS app in this repository.
- Initial Xcode: 26.6 (17F113); current installation: Xcode 27 (27A266a).
- Current native validation compiler: Xcode 27's Swift 6.4 with the macOS 27 SDK.
- Runtime: macOS 26.6.2. macOS 27 runtime has not been tested.
- Baseline: clean `main` working tree before this task.
- Build artifacts: `/tmp/bedrock-pilot-derived`.
- Detailed execution logs: `/tmp/bedrock-pilot-validation`.
- Initial Xcode Debug build: passed (`model-discovery-build.log`, 2026-09-15).
- Full native fallback builds through 42 passed. Build 42 runs in both validation apps with preserved isolated data. The newer Xcode installation requires license acceptance, so the current source is built with an isolated SwiftPM executable using all registered app sources, generated Core Data classes, resources and local dependency checkouts. This is not a substitute for the pending Xcode Debug/Release build checks.
- The earlier baseline build log was in temporary storage and is no longer present;
  it is not being used as acceptance evidence.

## Initial findings from source inspection

These findings motivated the implementation. They describe the initial source;
executed checks and remaining acceptance items are recorded separately below:

1. `MainView` and `SettingsView` merge model dictionaries by keeping the existing
   provider array, dropping inference profiles for providers already present.
2. `ChatView` and `MessageBarView` install local key monitors without removing them.
3. `ChatViewModel.ToolUseTracker.shared` shares stream state across conversations.
4. The streaming tool loop executes on the first completed tool block and returns
   before draining the response, losing later tools and usage metadata.
5. Non-streaming Converse builds a request with `inferenceConfig: nil`, ignoring
   the configuration the UI exposes.
6. Message updates perform synchronous full-history persistence repeatedly.
7. AWS endpoint edits commit only on Return.
8. The Bedrock API key is stored in UserDefaults.
9. Empty-thread cleanup can delete meaningful unsent work once drafts are added.
10. The empty main screen supplies no useful configuration/recovery action.

## Executed results — 2026-09-15–16 UTC

- Latest core suite: **57 XCTest tests passed**, 0 failures, 2.010 seconds (`core-36/tests.log`, `core-36-run.log`). The native rendering/search/clipboard suite passed **21 XCTest tests**, 0 failures, 1.417 seconds (`native-render-paste-36.log`, `native-markdown-tests/tests.log`). The built XCTest bundles were executed directly using Xcode’s `xctest` agent because the CLT installation does not supply XCTest itself. Earlier 24-, 39- and 45-test core runs also passed.
  The current suite includes eleven conversation/preference compatibility regressions.

  Tests execute real filesystem operations and spawned processes, including child
  cancellation. They also cover per-thread state round trips, malformed storage,
  skill parsing/selection, literal demo variables, DST scheduling, context/tool
  grouping, argument quoting, data migration, dotted model IDs and profile routing.
- `xcodebuild ... -configuration Debug ... CODE_SIGNING_ALLOWED=NO build`:
  **passed** with the model discovery changes. The first intermediate build failed
  while new model sources were being registered; the subsequent build included
  them and passed. Release and the existing Xcode test target are still pending.
- Launched the actual SwiftUI app using `scripts/run-preview.sh`, with
  a separate bundle ID, preferences, Keychain service and temporary data directory.
  Accessibility inspection and screenshots succeeded. At 22 seconds after launch,
  `ps` reported CPU **0.1%** and RSS **154,048 KiB**. This is an idle observation,
  not a general performance benchmark.
- Native composer → Return → Nova Micro → streamed response → completion footer:
  **passed**. A Korean message pasted through the native clipboard remained intact,
  and the next request remembered `파란별`. Unicode key synthesis by the automation
  tool initially produced punctuation only; the input was checked before resending
  via paste. Korean IME composition itself is still pending.
- AWS control-plane discovery verified 31 commercial regions, including 132 active
  foundation IDs before the requested legacy exclusions. `ap-east-1`,
  `me-central-1`, and `me-south-1` could not be verified with the current connection.
  GovCloud was not queried using commercial credentials. Snapshot generation copies
  no account IDs, application profiles, credentials or ARNs into the app.
- Actual Converse call to `us.openai.gpt-5.6-luna` with
  `additionalModelRequestFields.reasoning.effort = "none"` returned `BEDROCK_OK`
  (14 input, 8 output tokens). The older `reasoning_effort` field was rejected.
- Actual GPT-6 Astra calls established that the same nested `reasoning` field is
  required, and `none` is rejected. AWS reported supported efforts
  `low`, `medium`, `high`, `xhigh`, `max`. A later native GPT-6 request succeeded and returned `BRIDGE_42`. Switching the same chat to Nova 2 Lite and asking for the remembered code returned `BRIDGE_42` again.

## Chat and compatibility pass

- Native Astra → Nova switch preserved the conversation ID, all messages, an unsent draft and the attached local `Tests/Fixtures/model-switch.txt` file. The follow-up was sent after removing the attachment. Per-message origin model IDs and the active model were inspected in the persisted JSON (`native-model-switch-evidence.json`).
- Released unified/legacy history fixtures cover attachments, tool results, reasoning signatures, camel/snake case keys and both date formats. A first-write migration creates an exact backup. Corrupt, future-version and wrong-chat files cannot be overwritten by an empty conversation.
- Request replay preserves stored content while adapting foreign reasoning signatures and tool blocks for a model switch.
- System appearance initialized from the existing preference; Dark was selected in Settings and survived an app restart. The full Light/Dark control matrix remains open.
- App launches use the `PilotValidation` bundle and isolated data directory. Existing user app storage is not the validation destination.

## UI findings from actual execution

- **Startup update loop:** unchanged `MenuBarExtra`/selection binding values were
  republished. Equality guards were added. The launched build is responsive and
  the idle sample above no longer shows a busy main thread.
- **Skills page overflow:** entering Skills pushed the page header and upper
  sidebar off screen, reproducible even after zooming the window. The root split
  view now receives the window's actual geometry; revalidation is pending.
- **Following streaming output:** after a third message, growing content disabled
  auto-scroll even without a user scroll gesture. Follow mode is now separated
  from the visible-bottom measurement; revalidation is pending.
- The old image starter still advertises Nova Canvas. This will be updated to the
  requested active-model scope.

## Model sources checked

Primary sources were AWS `ListFoundationModels` / `ListInferenceProfiles` and the
AWS Bedrock user-guide pages `models-api-compatibility`, `models-endpoint-availability`,
`bedrock-mantle`, and the individual GPT-6 Astra, Grok 4.3 and Gemma 4 model cards.
The user's catalog URL requires Midway in this environment; the app does not
depend on it or introduce a catalog sign-in.

All unverified UI controls and live modalities remain open in the acceptance
inventory. A catalog entry is not evidence that inference with that model works.

## Settings freeze reproduced during validation

- Native build 12 reproduced a main-thread stall immediately after enabling Astra custom parameters. The process reached 99.1% CPU and a 4.3 GB physical footprint. The stack sample is `astra-settings-hang-sample.txt`.
- The sample remained inside `NSSliderTickMarks._rebuildTickMarkRectCache`: SwiftUI's `step: 1` built a tick for every value in the 1–128,000-token range. This was introduced by the native slider conversion and is not an AWS inference timeout.
- The fix keeps the native slider continuous and rounds its bound value, preserving exact numeric entry without constructing a large tick collection. Temperature, Top P, thinking budget and the shared slider wrapper follow the same approach.
- Model configuration updates now publish their model/profile aliases in one dictionary mutation and skip unchanged values. Post-fix native stress results are recorded below after execution.


## Scroll and menu pass (native builds 14–17)

- Imported `Tests/Fixtures/scroll-stress.json` through the native File menu: 60 fixed messages, including Korean/English text, code, tables, thinking and tool metadata. These are UI fixtures, not model-generated responses.
- Build 14 completed 12 outer-scroll actions, 10 actions targeting rendered Markdown, and 14 wheel actions at the same visible conversation coordinate. The coordinate run reached both the top and the bottom, with directionally consistent movement and no reproduced hang.
- Eighteen process samples recorded a maximum main-app RSS of 160.4 MiB and 0% CPU after interaction stopped. These observations exclude WebKit helper processes and are not a general benchmark. Artifacts: `scroll-build14-process-samples.json` and `scroll-build14-ui-evidence.json` under the isolated validation directory.
- Code highlighting rendered with bundled Highlight.js resources. Copy code pasted the exact original `SCROLL_01` Swift snippet into the composer. Thinking and tool disclosures opened; the tool detail window switched between Input and Output and closed with Done.
- Build 16 showed white navigation/toolbar icons and a white enabled Send circle with a black arrow in Dark appearance. The welcome screen no longer contains a Bedrock symbol. Cmd-N opened a focused new composer while preserving the fixture draft; Cmd-B hid and restored the sidebar.
- Cmd-K and View → Command Palette exposed a shared-state notification bug. An explicit `ObservableObjectPublisher` bypassed Combine's synthesized wiring for `@Published` properties, leaving some menus/navigation unchanged until another state mutation occurred. A small compiled Combine reproduction confirmed notification counts of 0 (explicit publisher) versus 1 (synthesized publisher). Build 17 restores the synthesized publisher while keeping draft batching. The menu matrix records revalidation separately.

## Native Markdown and streaming investigation

- Native build 21 rendered ordinary completed Markdown with native text, code and
  table views. The 60-message fixture had zero WebKit accessibility areas.
  Sixteen subsequent wheel actions reached both ends monotonically; command
  palette search opened the correct fixture, Find located `SCROLL_01`, Copy code
  preserved its exact source, and tool Input/Output details retained JSON types.
- A real 10,690-byte Astra reply exposed the streaming regression: the app used
  one plain `Text` for the whole growing response. Markdown remained literal
  until completion. `native-21-stream-sample.txt` showed 3,965/4,164 main-thread
  samples in SwiftUI layout, including expensive Core Text glyph measurement.
  A UI snapshot during this condition took about 61 seconds.
- Build 23 removed the plain-text streaming path, parses updated Markdown on a
  worker actor, avoids caching every stream prefix, and publishes token updates
  to only the active message row. Converse and Mantle display updates are
  coalesced; checkpoints occur every two seconds and final buffers flush on
  completion, Stop or error. Completed code blocks retain bundled highlighting.
- An actual 18,099-byte / 3,881-output-token Astra reply rendered code while Stop
  was still visible, then applied syntax coloring. Headings, emphasis and nested
  lists were inspected in the completed reply. It completed in 70.6 seconds.
  This is an observed request duration, **not a controlled model-speed benchmark**.
- A larger, repeated list/code workload found a second bottleneck in build 23.
  `native-23-second-stream-sample.txt` placed 2,331/2,480 main-thread samples in
  repeated nested stack measurement and alignment. The model completed, but a
  wheel/snapshot call took 34.6 seconds. This stress check failed acceptance.
- Build 24 flattens Markdown containers and caches each block's measurement by
  content, width and font size. It also removes an unnecessary assistant HStack.
  A similar 60-section response completed in 65.6 seconds. A separate remaining
  issue was observed: the outer lazy chat stack could estimate an empty area near
  the end of a growing response. Build 25 replaces those estimates with exact
  outer geometry and makes the explicit jump-to-latest action immediate.
  Its live scroll acceptance is recorded separately after revalidation.
- Four new renderer XCTest cases pass: open fences, nested/continued lists,
  quote/table/code structure, and width-dependent layout for 420 native rows.
  The initial 720 → 420 → 720 width test took 0.17 seconds; a repeat while
  compiling took 0.42 seconds. These measure native layout, not AWS latency.
  The harness compiles the production renderer, palette and type scale and
  does not initialize AWS clients or read application storage:

  ```sh
  python3 scripts/validate-markdown-rendering.py \
    --markdown-package /path/to/swift-markdownkit \
    --developer-dir /Library/Developer/CommandLineTools
  ```

  Detailed evidence: `native-markdown-tests/tests.log`,
  `native-23-stream-process.json`, `native-24-stream-process.json`.

## Demo routing and control simplification

- Native build 21: Demo library → Create image chose Stable Image Core 1.0
  (`stability.stable-image-core-v1:1`) in `us-west-2`. The user-visible editable
  prompt required Send; the actual request produced a local image in 2.7 seconds.
  Image-editing/upscale services are excluded from this text-to-image preset.
- Image and embedding requests resolve their invocation ID through the regional
  catalog. Stability editing retains the selected profile and accepts the
  required image/mask inputs. Six added core tests cover demo model selection,
  Luma request validation, legacy thread decoding and readable failure messages.
- Luma video now has native controls and a StartAsyncInvoke/poll/download path.
  Its request schema is tested. No live S3 video run has been performed, and no
  bucket was provisioned as part of validation.
- Native 21/23 show one model selector and response-settings control in the
  composer, sidebar-only New chat/Settings, and a centered welcome composer.
  Light-mode Send is a black circle with a white arrow; previous Dark validation
  showed the inverse. AWS settings no longer retain the gray search-row fill,
  and the API key input has a readable 34-point height.
- Tools & MCP settings now offer connected-tool schema inspection. This control
  still needs a live connected-server check; the chat tool-detail fixture is
  already validated separately.

## Performance regression follow-up

- Stress validation uses `Bedrock Performance.app`, bundle
  `AWS.Amazon-Bedrock-Client-for-Mac.PerformanceValidation`, with its own
  preferences and data. It contains assistant-created test conversations and
  user-created conversations, which are preserved. Both it and
  `Bedrock Validation.app` are now updated to the current native build, retaining
  their separate data directories, preference domains and Keychain services.
- Build 25's 60-section live request still used substantial app CPU: 120
  process samples over 61.1 seconds had median 76.45%, peak 101.5%, and peak
  app RSS 503.4 MiB. This is an intermediate regression, not the released-app
  baseline. Build 26's longer history reached a 1.1 GiB peak physical footprint.
- The original `HEAD` renderer uses one WebKit view per Markdown response.
  Unbounded native Markdown had expanded long responses into hundreds of
  selectable SwiftUI blocks. The revised policy limits native rendering to
  4,000 UTF-8 bytes and 48 blocks, then uses the original WebKit path.
- WebKit loads a document once. Subsequent stream updates replace changed
  top-level blocks and preserve completed DOM nodes. Only one update is in
  flight; newer updates replace pending content. Font size uses a CSS variable.
  A repeating 100 ms code-button scan and its mutation observer are removed.
  Copy code preserves leading and trailing whitespace.
- A viewport-unmount experiment caused repeated WebView creation when its
  asynchronous height became available (`native-29-startup-sample.txt`).
  It was removed. The chat retains the original exact outer stack geometry.
- Six renderer XCTest cases pass, including a real WebKit test verifying that
  streaming retains an existing paragraph node and selected Korean text,
  preserves exact code text, appends/removes blocks, and updates font size.
  Evidence: `native-markdown-harness-run-28.log` and
  `native-markdown-tests/tests.log`.
- A separate race prevented a model selected during generation from applying:
  `setIsLoading(false)` deferred its write, but `changeModel` checked the old
  loading value immediately. Loading changes now occur synchronously on the
  main actor. Failed model changes retain the selection and draft and cannot
  silently send with the previous model. Native 31 end-to-end revalidation passed
  as recorded below.
- The older local-folder demo accepted a default folder in preflight while advertising
  no file tools because the thread had no folder ID. New threads capture the
  default folder; existing folder-demo threads pin it on retry. Preflight checks
  the actual folder and both Read files and List files. Native 35 supersedes this
  project-based flow: the Files destination and project picker are removed, and
  the demo accepts an ordinary folder-path variable. Old project metadata is
  retained for decoding and migration to an optional working directory.

## Measured recovery and live regression results (native 31–32)

- The same 60-section Markdown/code request shape was exercised with Astra in
  the long validation thread. Native 31 recorded 102 process samples during
  active generation: median app CPU **8.5%**, peak **42.3%**, and peak app RSS
  **159.6 MiB**. The earlier native-25 observation was 76.45%, 101.5%, and
  503.4 MiB. Histories differ and WebKit helper memory is excluded; this is
  evidence of recovery from the intermediate regression, not a controlled
  comparison against the original Release app or an inference-speed benchmark.
  Evidence: `performance-lab/native-31-stream-process.json`,
  `performance-lab/native-25-stream-process.json`.
- During that Astra request, the composer selected Nova 2 Lite for the next
  response. The typed draft survived completion. Sending it produced
  `NEXT_MODEL_OK`; both the user/assistant history entries and completed run
  `E0A98A79-2B06-49C5-AC28-998ABBFC7826` record
  `us.amazon.nova-2-lite-v1:0`.
- A subsequent real Nova stream was cancelled with Escape at
  `2026-09-15T21:23:45.233Z`. The persisted cancellation time is
  `21:23:45.250280Z`, approximately 17 ms later. The final partial reply
  preserved 6,297 UTF-8 bytes through section `CANCEL_LIVE_026`.
  This measures local cancellation acknowledgement, not remote server shutdown.
  Run: `47DFEF0F-22C1-4770-A325-441D90E5990B`.
- Native 31's font enlargement exposed a remaining clipping bug: the last
  section disappeared because offscreen WebKit animation frames did not deliver
  the new height. Native 32 returns the extent directly from its DOM update and
  measures resize events without an animation-frame dependency.
  Two font increments, reset, and a 1080×740 → 903×655 → 1080×740 window
  round trip retained the final paragraph. Copy code pasted the original code
  into the composer. The draft was cleared afterwards.
- Native 31 Settings → Models showed one default-model picker with a read-only
  ID beneath it. Astra response settings accepted 128,000 tokens; a slider
  decrement produced 115,200, which survived closing/reopening. The original
  8,192 limit was restored. No slider hang reproduced.
- Native 32's local-folder demo used an assistant-created two-file folder.
  One List files and two Read files calls completed, then Astra returned a
  grounded review. The README tool's JSON input and numbered output were
  inspected inline and through both tabs of the detail sheet.
  Thread: `10E0729B-2503-40F3-A370-0C69EEF61E66`.
- Escape closes tool details (native 32/35); Done was separately exercised in
  native 14. Cmd-D while the sheet or Settings has focus
  retained the background thread. Cmd-N from Settings brought forward the
  centered, focused new-chat composer. Demo preparation uses that same layout.

## Find follow-up

- Native 32 reproduced an exact navigation bug: searching `CANCEL_LIVE_026`
  reported one result but displayed section 13 without highlighting it.
- Find now routes by message UUID directly to its renderer. The WebKit result
  returns a line rectangle to the native outer scroll view; the old competing
  animations, per-message stale callback and broadcast to every WebView are
  removed. Search includes code blocks and text split by inline Markdown.
- Search ranges/snippets/highlights now use UTF-16 and composed-character
  boundaries. Cache entries are invalidated when messages change, and Find
  matches the entered phrase consistently with its result counter.
- **11 renderer/search XCTest cases passed**, 0 failures, in 1.07 seconds.
  The four added checks cover Unicode range/highlight safety, changed/appended
  message caches, phrase matching, and real WebKit match counting/line
  rectangles/code/inline markup/clearing. The earlier seven renderer tests
  include the offscreen height regression.
  Evidence: `native-markdown-harness-run-33.log` and
  `native-markdown-tests/tests.log`.

## Skills, local access and compatibility recovery (native 35–40)

- Fresh preferences enable all eleven built-in tools with Allow enabled tools
  and unrestricted local file paths. Explicitly restricted older profiles are
  preserved; untouched old Chat-only defaults migrate. Paths accept absolute,
  home-relative and configured-working-directory-relative values. The optional
  allowlist applies to file tools; it is not represented as a shell sandbox.
- Native 35 called `local_list_skills`, `local_read_skill` for `code-review`,
  and `local_run_command` for `/usr/bin/printf 'EXEC_VALIDATED_35\n'` in `/tmp`.
  All completed without an approval dialog. The shell returned exit 0 and the
  exact marker. Input/output expansion, both detail tabs and Escape worked.
  Cmd-D while the tool sheet was focused did not trash the background chat.
  Evidence: `native-35-skills-exec-evidence.json`.
- Native 35 Cmd-N opened a separate blank thread with the current model and
  focused composer. Cmd-D trashed only that assistant-created blank thread and
  restored the previous thread's exact draft. The draft was then cleared.
  Native 36/38/40 Cmd-N also opened a new thread and retained the selected model.
- The old bundled code-review skill is upgraded only when its contents exactly
  match the old bundled version. Both app data directories contain the updated
  skill and `SKILL.pre-local-access.md` backup. Custom content is covered by
  the core regression suite.
- Native 38's ordinary “which skills and tools?” question found the actual
  skills and shell tool, but also advertised an unregistered parallel wrapper.
  Native 40 now supplies the exact tool registry built for that request,
  including connected MCP IDs. Requests without tool support receive an empty
  registry. A fresh, unhinted question performed List skills and returned the
  five actual installed skill IDs/names and all eleven exact local tool IDs,
  with no namespace prefixes or invented parallel tool.
- In the same native 40 conversation, `local_run_command` with the relative
  directory `../../tmp/bedrock-pilot-validation/tool-cwd-fixture` returned the
  canonical `/private/tmp/...` working directory. `local_git` returned that
  repository's status. `local_write_file` and `local_read_file` round-tripped
  `RELATIVE_CWD_40` in that same isolated directory. All four tool calls
  completed without an approval prompt.
  Evidence: `native-40-skill-registry-local-path-evidence.json`.

## Mixed clipboard and cold-history recovery (native 36)

- Native Chrome copied an expanded local fixture using Cmd-A/C; the app pasted
  it with Cmd-V. The fixture contained 240 paragraphs of Korean/English/emoji
  text (34,944 UTF-8 bytes including the fixture page header) and ten 1600×900
  PNGs. The composer displayed ten images plus one pasted-text attachment and
  remained responsive. The tool observed the ready UI 806 ms after issuing
  paste; this includes automation overhead and is not an isolated benchmark.
- Full image preview reported 1600×900 and Escape returned focus to the composer.
  Sending the attachments to Nova 2 Lite completed and returned the final
  `PASTE_END_36` marker. The persisted user message contains all 240 paragraphs,
  both boundary markers, ten image payloads and one pasted-text entry.
  Evidence: `native-36-browser-paste-evidence.json`. Earlier attempts with a
  collapsed browser preview or the automation clipboard were discarded and
  are not counted as successful full-text validation.
- History decoding and Markdown preparation now run off the main actor.
  Initial empty-thread cleanup skips histories larger than 16 KiB and rechecks
  small-file candidates before deleting. The first-ever migration of every
  history file from an older release still needs a dedicated performance pass.
- Cold opening the long conversation restored all replies through
  `CANCEL_LIVE_026`. The observed click-to-accessibility interval was 1.47 s,
  not a measured render TTI. Fifty app-process samples over about ten seconds
  peaked at 87.3% CPU and 194.55 MiB RSS during cold loading. WebKit helper
  processes are excluded and no original-Release comparison was run.
  Evidence: `performance-lab/native-36-cold-open-process.json`.
- Find for `CANCEL_LIVE_` reported 28 matches. Previous wrapped to 28/28 and
  visibly highlighted `026`; Previous highlighted `025`; Next/wrap returned
  to the first prompt match. Done closed Find and manual up/down scrolling
  remained usable. Code-copy pasted the original Swift snippet, including
  whitespace, into the composer. The test draft was cleared.
- Native/core tests cover bounded regular-file reads, corrupt-history
  preservation, HTML sanitization/CSP-compatible updates, stable attachment
  IDs, ordered file imports, cancellation followed by a new import, full image
  preparation limits and main-actor responsiveness during import.

## White appearance refinement (native 37–42)

- White sidebar and Settings backgrounds no longer use the gray sidebar/window
  materials. Search/API-key fields and light content surfaces follow the same
  white palette; dark surfaces remain separate dynamic colors.
- New chat, Demo library, Automations and Activity stay above the scrolling chat
  list, with the account/settings footer fixed below it. Native wheel scrolling
  confirmed that the top navigation no longer clips or scrolls out of view.
- The light main toolbar now matches the white canvas. AWS Settings was inspected
  with full-width readable region/profile fields, API-key entry, refresh action
  and connection status. The current scrollbar/theme/keyboard follow-up is
  tracked individually under WS01–WS09 in the acceptance inventory.
- Native 41 removes the sidebar scrollbar's opaque slot even when SwiftUI
  restores the current system's Always-visible style after layout. The rounded
  thumb uses native NSScroller tracking. Dragging it from bottom to top changed
  the sidebar's accessibility value from 1 to 0; the conversation scroll value
  stayed at 0.970297. Wheel scrolling and the fixed navigation remained usable.
- Explicit Dark → Light → System appearance changes retained the selected
  thread and the exact `THEME_DRAFT_41` draft. Compact sidebar on/off retained
  the fixed menus and footer. System appearance and normal spacing were
  restored and the temporary draft was cleared. White and dark Settings and
  main-window surfaces were visually inspected.
- Settings search for `model` returned the expected model/connection/tool
  settings. A no-match query and Clear search restored normal navigation.
  Models showed one default-model picker, a read-only Astra ID, the nearby
  system-prompt preset, an unclipped editor and readable switches.
- A keyboard regression found during this pass took focus from the native
  sidebar after every selected chat. Native 42 preserves list focus while
  navigating history. Consecutive Down then Up selected the adjacent thread
  and returned without clicking again. Cmd-B hid/showed the sidebar. Demo
  library, Automations and Activity buttons opened their expected pages.
  The New chat button and Cmd-N each produced a centered blank composer with
  GPT-5.6 Terra and keyboard focus. Cmd-D trashed only the newly created empty
  test chats and selected the most recent remaining conversation.
- Automatic scrollbar fading under a different macOS system preference and
  Increase Contrast remain separate unchecked scenarios. This pass did not
  change system-wide scrollbar or accessibility preferences.

## Apple design references reviewed

- Apple's Human Interface Guidelines → Materials recommends using Liquid Glass
  for controls/navigation with care for legibility, and keeping content
  surfaces visually restrained. The light sidebar intentionally uses a white
  surface to satisfy the user's requested appearance.
- Apple's Design What's New page listed 2026 updates and macOS 27 Figma/Sketch
  UI resources when viewed during this task. This is design-source review,
  not a claim of macOS 27 runtime validation.
- Sources visited in Chrome: `https://developer.apple.com/design/human-interface-guidelines/materials`
  and `https://developer.apple.com/design/whats-new/`.

## Foxl parity and regression suites (native 43–60)

The later source audit is itemized in [FOXL_CONVENIENCE_TODO.md](foxl-parity.md)
and [foxl-settings.md](foxl-settings.md). It includes gaps as
well as implemented features; the presence of a checkbox does not imply parity.

- Builds 45–52 exercised sent-message editing and branching, queued prompts
  with attachments, queue editing/removal/interruption, paused queue recovery,
  and relaunch without automatically sending restored work. Continuous
  Markdown selection, exact code copying, slash-skill selection, and actual
  AWS-backed skill/command execution were also exercised.
- In a real conversation, Nova 2 Lite ran a local command and GPT-6 Astra
  recalled its output after an in-chat model switch.
- The core suite on 56 executed **88 tests, zero failures**. The app integration
  suite on 59 executed **63 tests, four opt-in public-network skips, zero
  failures**. The native-renderer suite on 60 executed **33 tests, zero
  failures**; 32 overlap the app suite and must not be added as unique cases.
- Local MCP integration cases start actual fixture processes. They cover
  arguments, environment, duplicate tool names, nested/structured results,
  stderr backpressure, timeout, cancellation, and reconnect isolation.
- Native 58 reproduced a Settings-close crash after inspecting all nine
  panes. Native 59 corrected window ownership. Six close/reopen cycles and a
  lifecycle regression passed. This was a crash fix, separate from the later
  input/scroll performance investigation.
- Nine Xcode UI test methods were type-checked with Swift 6 on 64. The local
  Xcode UI runner was **not executed**: the installed Xcode's license is not
  accepted. The task did not accept that agreement. The Command Line Tools
  compiler and installed XCTest runner were used for the executed suites.

## Measured Validation recovery (native 61–64)

The user's report was reproducible: Validation 50 was a different executable
from the newer Performance 61. Both were tested with the same synthetic
1,000-message conversation, 1240×780 window, Light appearance, no inference,
and compilation stopped.

| Build | Typing median | Typing p95 | Six-second scroll probe |
| --- | ---: | ---: | --- |
| Validation 50, older Debug executable | 73.03 ms | 81.52 ms | 6.05 s, completed |
| Performance 61, Release | 261.88 ms | 280.26 ms | Exceeded 20 s |
| Performance 62, Release | 8.59 ms | 13.99 ms | 5.99 s, completed |
| Validation 62, existing Validation data | 7.19 ms | 12.43 ms | 5.98 s, completed |
| Validation 64, three repeated passes | 8.30–9.78 ms | 12.48–17.07 ms | 5.98–5.99 s, all completed |

These measure input-event to accessibility-text update, **not FPS, display
frame time, or model latency**. Each typing pass sent 61 characters. Each
scroll pass sent 360 events and used small window-attribute probes rather than
expensive whole-transcript accessibility walks. All six 64 passes reported
zero probe failures. This is a controlled comparison on one Mac.

Profiling 61 showed repeated scene/menu/view-graph work. The app's root
`@FocusedValue` observed newly constructed command closures on chat updates.
Build 62 moved that observation into `WorkbenchAppCommands`, keeping it out of
the app scene. The 61→62 comparison retained the same Release configuration
and workload. See [performance.md](../performance.md) and
`scripts/measure-ui-responsiveness.swift`.

Validation 64 was installed in the existing `Bedrock Validation.app` bundle
with identifier `AWS.Amazon-Bedrock-Client-for-Mac.PilotValidation` and its
existing data directory. Its executable is Release despite the inherited
`Amazon Bedrock Debug` filename. SHA-256:
`b369a8e764b626c8e8bab95d5aa5fb0a57d1f117d3477053e62a0356a572e5f1`.
The old Validation 50 executable and pre-update data were preserved.

All **28 original nonempty history files, containing 178 messages, and three
original nonempty drafts remained byte-for-byte unchanged**. The existing
cleanup removed two old empty history files. All content-producing checks
used separate synthetic conversations.

## Actual interaction checks (native 62–64)

On 62, all nine Settings panes were inspected in Light at 850×700 and Dark at
740×650; no horizontal input clipping was seen. Five close/reopen cycles
passed. Light/Dark/System switching retained the selected chat and draft.
This is layout/lifecycle coverage, not a claim that every setting was toggled.

Actual Bedrock requests on 62 verified Nova 2 Lite → GPT-6 Astra context and
draft preservation. Skill listing/loading and
`/bin/sleep 4; /usr/bin/printf 'EXEC_VALIDATION_62\n'` completed through the
tool loop. A queued follow-up returned `QUEUE_62_OK BRIDGE_62`. Tool input and
output copied exactly, output Find highlighted the requested match, and the
detail sheet closed normally.

The 64 accessibility follow-up corrected toolbar button roles, labels and
actions and stopped popover identifiers from replacing child search IDs.
Actual 64 checks passed:

- Sidebar click and ⌘B, Back click and ⌘[, distinct ⌘N chats, and ⌘D recovery
  of the preceding synthetic chat's exact draft.
- One 32×32 Sidebar, Back, and Search target; centered global search through
  the original upper-right button and ⌘K; outside click and Escape dismissal.
- ⌘F opening only chat Find; Demo/Activity navigation; Settings open/close;
  GPT-6 Astra selection with a retained draft.
- Four open/zoom/fit/close cycles for a 4096×3072 generated-image fixture.
  Both copied and saved PNGs were byte-for-byte identical to the original.
  Opening observations were 0.39–0.61 seconds including automation.
- A 232,237-byte multilingual paste became an editable text attachment in
  0.295 seconds including automation. Exact text survived edit/save/reopen.
  Mixed text and two 4K PNGs were ready in 0.842 seconds.
- After graceful quit/relaunch, ordinary-chat text was visible in 0.613
  seconds and all three attachments in 0.995 seconds; selected model and
  edited text remained intact. An actual Nova 2 Lite request using that
  document and both images returned **`EDITED_PASTE_END_64 2`**.
- HTML-only paste removed script/style/iframe content and retained entities
  and multilingual text. A 104,115-byte, 2,000-paragraph HTML fixture became
  an 84,029-byte text attachment in 0.294 seconds, retaining its final marker.
- The 1,000-message fixture opened in 0.517 seconds after restart and
  0.313–0.329 seconds on three warm reopenings, including automation.
  Rendering was bounded to 32 → 64 → 96 messages and remained at 96.
  Global search found the oldest passage and opened Find with two matches.
  Three resize/scroll cycles remained responsive.

Visual inspection also found an **unresolved paging-anchor regression on
64**: loading an earlier page moved the first visible fixture turn from 484
to approximately 474. Bounded rendering and fast loading do not establish
stable reading position. PV18/C33 remain unchecked while the follow-up is
implemented and measured.

This specific regression was resolved and rechecked in 70; the later native
viewport results below supersede its open status on 64.

The Release 64 app integration suite executed **64 tests: 60 passed, four
opt-in public-network cases skipped, zero failures**, in 3.90 seconds.
Cancellation/timeout error logs belong to deliberate negative-path MCP tests.
Local evidence: `/tmp/bedrock-pilot-validation/comparison-64/` and
`/tmp/bedrock-pilot-validation/tests-64/app-tests.log`. Clipboard fixtures
preserved and restored the previous clipboard contents.

## Native viewport and latest Validation executable (70)

Validation 70 was built in Release, installed into the existing Validation
identity/data directory, and checked against all 122 app Swift source files
in the workspace. Its current runtime resource bundles and bundled highlighter
were copied too. Pre-sign executable copying and the Mach-O UUID were verified;
ad-hoc signing changes the installed executable hash.

Installed executable SHA-256:
`5ebb23a560db84bfcec7da47f26d5050906c8b60b78a58860108781d6d797628`.
Mach-O UUID: `FEB67D98-3F52-3231-AE8A-2E9358C4DDC8`.
The inherited executable filename still contains “Debug”; its build
configuration is Release.

The bounded native viewport preserves message coordinates through earlier
and newer paging, including eviction at the 96-message cap. Five additional
page operations retained exactly the prior Y coordinate. Three Activity/Back
round trips retained the same reading position, and three window-size changes
retained it as well. Build 69 had failed the second round trip: SwiftUI could
dismantle anchors before AppKit's removal callback, and a newly restored view
had no fallback snapshot. A minimal native reproduction returned nil before
the correction and the original offset afterward.

After compilation stopped, three typing passes measured median
**8.10–8.92ms**, p95 **12.01–13.69ms**, maximum **59–73ms**. Three 360-event
scroll passes each completed in **5.984s**, with no failed probes. These are
event/AX measurements, not display frame times. The same fixture/window was
used for the older Validation 50 and Performance 61 comparison.

The complete 70 Release integration suite executed **68 tests: 64 passed,
four optional external-network tests skipped, zero failures**, in 3.50s.
The 11 UI test methods type-checked; local Xcode UI runner execution remains
unavailable under the unaccepted Xcode license. Project membership and
`actionlint` passed. No hosted CI run is claimed.

Actual 70 controls rechecks passed: one compact Sidebar/Back/Search control,
click/⌘B, Back/⌘[, ⌘N/⌘D draft behavior, ⌘K/outside/Escape global search,
⌘F chat Find, model selection with retained draft, and Settings open/close.
The 1,000-message fixture reopened in 0.477–0.489s including automation; a
complete app relaunch to its saved history took 0.929s.

In a separate Showcase identity, a welcome draft containing **93,019 UTF-8
bytes and a 4K image** restored in 0.943s including launch/polling. Exact
text was checked through the pasted-text editor. Sending the restored draft
to Nova 2 Lite returned **`WELCOME_RESTORED_70 1`**. Send is gated until
welcome attachment restoration/import completes.

The 28 original nonempty history files (178 messages) and three original
nonempty drafts remained unchanged. Evidence:
`/tmp/bedrock-pilot-validation/comparison-70/`,
`tests-70/app-tests.log`, and `showcase-70/welcome-restore/report.json`.
The preview-launch script now requires an explicit built-app path and
records source/installed versions and hashes, rather than silently opening
an older default Debug build.

## Source attachments and reliable build replacement (71)

The actual Attach files picker accepted `Median.swift`. Its 117 UTF-8 bytes
were preserved exactly and sent as a `txt` document, which the runtime accepts
for source/configuration text. Nova 2 Lite then called `local_list_skills`
and `local_read_skill` successfully and returned a review of the supplied
function. This used a dedicated Showcase identity, not an existing user thread.

Two integration regressions cover exact source/configuration bytes and
rejection of binary or oversized input. The 71 Release app suite ran
**70 tests: 66 passed, four optional external-network tests skipped, zero
failures**. Three typing passes measured median 6.46–7.55ms and p95
10.65–12.47ms. All three scroll passes completed without failed probes.
Evidence: `comparison-71/source-attachment/report.json`,
`comparison-71/performance/`, and `tests-71/app-tests.log`.

The preview script now verifies a fresh staged executable before signing,
retains the previous bundle, and avoids overlaying obsolete resources on the
new app. Actual isolated-script checks verified:

- Missing build arguments and identical source/destination are rejected.
- A running preview is detected through `/tmp` and `/private/tmp` aliases.
- A synthetic stale resource disappears from the installed bundle.
- The old bundle and a synthetic data marker remain intact.
- The selected build/version is recorded, opens a real window, and quits normally.

Evidence: `preview-script-71/report.json` and `preview-build.json` in that
directory. The installed hash can differ from the source after ad-hoc signing.

## Toolbar state and responsiveness (73)

A subsequent interaction pass found intermittent sibling accessibility labels
inside a single hosted toolbar item. Native toolbar groups now give Sidebar,
Back, Chat options, and Search their own item and label. Removing redundant
manual accessibility actions also restores the actual disabled Back state.
Visible glyphs remain 14pt; the native transparent hit targets are 40×38pt.

Validation 73 uses the existing Validation identifier and data directory.
All 122 app Swift files matched the staged build. Installed SHA-256:
`0c0a09108eb43e99d664b2666e5796e895af8d090cf99b87d2b785f38ac85e98`.
Mach-O UUID: `794367F7-A316-3C96-9CC4-74AE2F2E0A70`.

After compilation stopped, three typing passes measured median
**6.62–7.65ms**, p95 **11.76–14.29ms**, maximum **42–56ms**. Three scroll
passes completed in **5.984–5.987s** with zero failed probes. The Release
integration suite again ran **70 tests: 66 passed, four optional network
tests skipped, zero failures**.

Actual control checks passed for sidebar click/⌘B, Back/⌘[, ⌘N/⌘D with a
retained draft and model, global Search/outside click/Escape, ⌘F, model
selection, and Settings lifecycle. Distinct toolbar names remained correct
after these transitions. The native Chat options popover was verified with
an accessibility hit test: it is not included in the harness's `AXWindows`
walk. The earlier tree-only probe failure is retained separately from the
corrected interaction record.

Evidence: `comparison-73/controls/`, `comparison-73/toolbar/`,
`comparison-73/performance/`, and `tests-73/app-tests.log`.


## First-keystroke, clipboard and release preparation checks

A targeted first-keystroke investigation isolated the remaining empty-to-nonempty
composer cost to whole-store notification for the sidebar draft badge. Per-thread
observation reduced three first-character samples from 74.4–113.1ms to 28.95–35.77ms.
Ordinary typing and scroll results, methodology and limits are recorded separately
in [performance.md](../performance.md). Actual scrolling also retained direction and
its original position in a 720-event movement test, with no frozen interval of
0.2 seconds or longer in the active recording section.

Quick Access was opened with Command-Shift-K, dismissed with Escape, reopened,
and used to send a real request. The main conversation received `QUICK_ACCESS_OK`.
Tool disclosure, distinct input/output copy actions, full original output and
Find highlighting were checked separately from the transcript.

Native Command-V now advertises the file, HTML and image formats the composer
handles. AppKit previously disabled Paste for PNG-only clipboard data before the
custom handler could run. The native Paste-menu regression passes for file URLs,
HTML and image-only contents, and rejects editing when the text view is read-only.
The source-file handler also uses the same supported extension set as Attach files.

Actual checks on the updated app:

| Interaction | Result |
| --- | --- |
| Command-V with a valid `.swift` file URL | Attached in 0.256s; the existing text draft remained intact |
| Command-V with only a 3200×1800 PNG | Attached in 0.284s |
| Additional paste containing two PNGs and 87,406 UTF-8 bytes | Ready in 0.275s; all three images and one text attachment retained |
| Open Edit pasted text | The complete text, including its final marker, matched exactly |

A standalone test clipboard writer originally exited before macOS committed its
file-URL data. Its earlier “paste failed” result is invalid harness evidence, not
an application failure. The corrected check verifies a nonempty file-URL clipboard
before using Command-V. The PNG-only Paste-menu issue is a separate, reproduced
application defect and has its own regression.

The latest optimized app integration suite executed **73 cases: 69 passed, four
optional public-network checks skipped, zero failures**. It includes native
Markdown/clipboard/image, inference configuration, MCP transport, viewport and
window lifecycle checks. The local core suite executed **88 cases, zero failures**.
The loopback protocol fixture's two tests passed both locally and on GitHub.

GitHub run `35092401527` exposed a Swift region-isolation compiler issue in a
renderer test's detached-task tuple expression. A named Sendable result preserved
the same assertions and compiled in run `35093816527`; native rendering and
clipboard tests then passed there. Full-app compilation then exposed the stable
compiler's expression-complexity limit in `MainView`. Layout, lifecycle and
presentation now have separate opaque view expressions, retaining the same
modifiers and behavior. Run `35097704466` then passed all 88 core and 37
renderer/clipboard cases, but Swift 6.3.3 crashed during IR generation of an
actor-isolated `Int` callback. Inference bindings now use explicit setter
closures instead of converting method references to generic setters. UI
execution and release publication are tracked independently in the delivery
ledger, not inferred from a successful compile.

Updated Validation identity/data were retained. All 122 app Swift sources matched
the installed Release build; its Mach-O UUID is
`D4EE1420-D60F-3D1C-95A1-58FACDD07980`. The latest run includes the stable-compiler
view split and dependency removal. Of 73 integration cases, 69 passed and the
four explicitly optional network checks were skipped. A targeted 1,000-message
check retained the previous typing/scroll responsiveness, shortcuts, Settings
lifecycle and all four restored attachments.

Local evidence is in
`/tmp/bedrock-pilot-validation/release-preflight/app-integration-79/`,
`release-preflight/final-native-smoke/` and `usability-regression/after-fixes/`.
README media uses a separate demonstration identity with the same application
sources; see [capture details](../media.md).
