# Responsiveness investigation

## September 17, 2026: native conversation scrolling

The current conversation uses an AppKit scroll document with independently
hosted visible messages. Lightweight row positions cover the entire history;
views are created near the viewport and released as they move away. There are
no manual earlier/newer buttons or fixed message-count pages.

Main CI `35193102534` exposed a remaining SwiftUI update loop in the previous
lazy stack when a response finished while the reader was scrolled upward.
Profiling reproduced repeated platform-view updates without corresponding
text measurement or composer updates. The native container removes that shared
lazy-stack update path. A message retains its native text identity when
streaming ends, and image/document sheets belong to the conversation.

The final optimized candidate passed these targeted checks:

- Light and Dark: finish a controlled stream while reading an older passage
  in a 1,000-message conversation; its screen position remains unchanged.
  The composer accepts input, and returning to the latest response works.
- Reach the first message with one native thumb drag; search question 250;
  retain its position through three Activity → Back round trips and sidebar
  collapse/expansion; preserve the previous draft with ⌘N/⌘D.
- Open, zoom, fit and close a 4K image three times; inspect original tool
  input/output; preserve selected native text when streaming completes.
- Nineteen optimized native tests pass: fifteen viewport/controller cases
  and four container cases covering 10,000-message access with bounded views,
  earlier-row growth, width-driven reflow, and following versus reading.
  A new seek replaces an older destination while retaining a matching saved
  offset. Both frame and clip changes update available text width.

The final executable was measured after the navigation checks, at 1240×780,
Light appearance, with the same 1,000 synthetic messages and an empty composer.
No compiler or model request ran during the measurement.

| Probe | Events | Median | p95 | Maximum | Failures |
| --- | ---: | ---: | ---: | ---: | ---: |
| Typing | 61 | 6.40 ms | 11.57 ms | 43.96 ms | 0 |
| Scroll responsiveness | 360 | 1.56 ms | 3.45 ms | 18.36 ms | 0 |

Typing measures event-to-accessibility-text-update latency. Scrolling measures
small window-accessibility queries during six seconds of wheel input
(5.985 seconds observed). Neither is a display frame-rate measurement or a
guarantee for every workload. The final check is one pass; three earlier native
candidate passes measured 5.94–6.62 ms typing median and 10.66–10.97 ms p95.

Executable SHA-256:
`c91b50fc206df7ef054be2856aa621f858e22ebebd3122cc980295541a1b2667`.
Raw interaction captures and measurements are under
`/tmp/bedrock-pilot-validation/release-completion/native-transcript-final-interactions/`;
Light/Dark completion receipts use `native-transcript-final-reading-*`, and
the standalone tests use `native-transcript-unit-tests/native-controller-final-tests.log`.
These targeted receipts do not replace the final main CI and release gates in
the [completion audit](quality/todo-audit.md).

## Earlier September 17, 2026: SwiftUI continuous history

The earlier candidate also contained the full conversation without earlier/newer
buttons. It used SwiftUI to create offscreen rows and retained native text and
image views. The following results predate the native container above.

The first continuous-history implementation used a `List`. A main-thread profile
of an actual 1,000-message UI test showed AppKit's table accessibility proxies
creating offscreen hosting views while resolving the transcript. The process used
one full CPU core and approximately 1.2 GB RSS. Replacing that table with
`ScrollView` and `LazyVStack` removed that accessibility-driven row creation.
Subsequent native accessibility queries completed without the reproduced hang.

The optimized candidate was measured with the same 1,000 synthetic messages,
1240×780 window, Light appearance and empty composer, after compilation stopped.
No model request ran during measurement.

| Pass | Typing median | Typing p95 | Maximum | 360-event scroll probe | Failed probes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 8.66 ms | 13.27 ms | 46.93 ms | 5.984 s | 0 |
| 2 | 8.96 ms | 14.48 ms | 40.90 ms | 5.987 s | 0 |
| 3 | 8.93 ms | 15.98 ms | 45.84 ms | 5.984 s | 0 |

Typing measures event-to-accessibility-text-update latency, **not display frame
time**. Scroll duration includes the scheduled six seconds of wheel input; it is
not a frame-rate measurement. The executable SHA-256 was
`9585494528a3806e5bc467f4f0ab5df4080f398bef81045a917c4f4ee08ff108`.
These samples precede the subsequent scroll-start cancellation correction.

Searching for question 250 and returning through Activity → Back three times
retained its exact screen coordinate, with a measured difference of 0 pixels.
Further repeat testing exposed a separate lazy-layout race: SwiftUI corrected
the target's position by 1,104 points before updating or reattaching its native
view. Observing document height and converting that stale native frame was not
sufficient. The viewport now uses actual content-layout coordinates and retains
the pending target's measured position during temporary detachment.

The corrected optimized app passed the actual full-history scroll/search/return
scenario three consecutive times, including one thumb drag to the first message.
Finishing a controlled stream while reading an older passage also passed three
times. All 11 native viewport regressions passed in each repetition. This run
uses AWS SDK 1.7.85 and Smithy 0.252.0; temporary diagnostic logging was removed
before execution. The complete CI gates remain separate from these targeted
results in the [completion audit](quality/todo-audit.md).

Raw measurements, the window capture and executable identity are under
`/tmp/bedrock-pilot-validation/release-completion/full-history-scroll-inspection/`.
The following numbered-build measurements are historical comparisons; their
former 32/96-message paging implementation is no longer used.

## September 16, 2026: earlier input and scroll regression

The older **Bedrock Validation 50** was a different executable from **Performance 61**. The latter contained newer UI and history changes, but had a reproducible input/scroll regression.

Both apps opened the same synthetic 1,000-message conversation in a 1240×780 window. Tests ran on macOS 26.6.2, using an empty composer and no inference request. Compilation was stopped during measurement.

| Build | Configuration | Typing median | Typing p95 | Six-second scroll probe |
| --- | --- | ---: | ---: | --- |
| Validation 50 | Debug, older implementation | 73.03 ms | 81.52 ms | 6.05 s, completed |
| Performance 61 | Release | 261.88 ms | 280.26 ms | Exceeded 20 s |
| Performance 62 | Release, command observation fix | 8.59 ms | 13.99 ms | 5.99 s, completed |
| Validation 62 | Same fix, existing Validation data | 7.19 ms | 12.43 ms | 5.98 s, completed |
| Validation 64 | Latest UI fixes, three passes | 8.30–9.78 ms | 12.48–17.07 ms | 5.98–5.99 s each, completed |
| Validation 70 | Native reading-position restoration, three passes | 8.10–8.92 ms | 12.01–13.69 ms | 5.984 s each, completed |
| Validation 71 | Source/configuration attachments, three passes | 6.46–7.55 ms | 10.65–12.47 ms | 5.983–5.986 s each, completed |
| Validation 73 | Native toolbar accessibility, three passes | 6.62–7.65 ms | 11.76–14.29 ms | 5.984–5.987 s each, completed |
| Validation 75 | Tool and Quick Access corrections, three passes | 8.39–9.30 ms | 11.87–12.62 ms | 5.984–5.985 s each, completed |
| Validation 76 | Per-thread draft observation, three passes | 10.52–10.73 ms | 13.18–14.29 ms | 5.983–5.987 s each, completed |

These are event-to-accessibility-text-update latencies, **not display frame times or model latency**. Each typing pass entered 61 characters and restored its own draft. The scroll probe sent 360 events at a planned 60 events/second and queried only the window attribute every six events. No full transcript accessibility snapshots were taken during timing. Values are observations on one machine, not universal performance guarantees. Validation 64 and 70 each completed three typing and three scroll passes with zero probe failures. On 70, individual maximum typing samples were 59–73ms; RSS settled near 250MiB after the paging and resize checks.

Validation 71 and 73 also completed all six passes without a failed probe.
On 73, individual maximum typing samples were 42–56ms. Its fresh 32-message
viewport used approximately 174–177MiB RSS during these checks; this is a
different cache/workload state from the earlier 96-message paging checks.

The 61→62 comparison used the same data, window, fixture, and Release configuration. Validation 50 is retained as a user-reported reference; it has different history-layout code and a different build configuration.

## Cause and change

Profiling showed repeated SwiftUI scene, menu, and view-graph updates while typing and scrolling. `App` observed the closure-valued `workbenchCommands` focus value. Chat changes supplied new command closures, invalidating the app scene; rebuilding that scene also rebuilt the window and supplied commands again.

`WorkbenchAppCommands` now observes focus inside the menu graph. The app scene no longer observes those command changes. The 62 comparison changed only this observation boundary and kept the same shortcuts and actions.

The previous full-tree accessibility scanner was also unsuitable for performance measurements: resolving thousands of labels itself used substantial main-thread time. The replacement probe discovers the composer once and uses small, direct accessibility requests.

## First-character latency and observed scrolling

The first character in an empty composer remained slower than the rest of a
line. On the same 1,000-message fixture, three first-character samples on 75
were 74.4, 83.6 and 113.1ms. A composer that already contained a character took
25.7–28.6ms, isolating the empty-to-nonempty draft transition.

The sidebar draft badge subscribed to the whole workbench store. The first
character changed the badge and published the entire store again. A small,
per-thread `WorkbenchDraftIndicator` now updates only the affected row, while
the draft still persists normally. A native regression test verifies zero
whole-store publications during typing, correct badge transitions, and no
notification to another thread's badge.

The updated app measured 28.95, 35.77 and 34.74ms for the first character.
Ordinary typing medians did not improve in this comparison; the table reports
them separately. The fix addresses the larger first-character interruption.
All three scroll probes completed with no errors, and RSS was approximately
177–179MiB for the fresh 32-message viewport.

A separate 12-second wheel test checked actual content movement, not only
whether the app answered an accessibility query. It tracked a message's
vertical position at 20Hz while delivering 720 wheel events at 60Hz, away from
the scroll boundaries. There were no failed queries, stationary sample
intervals, or movements in the wrong direction; the final position returned
to its exact starting point. Maximum position-query latency was 1.56ms.

A simultaneous 16-second screen-area recording averaged 57.15fps. A cropped
transcript freeze scan found no frozen interval of 0.2 seconds or longer during
the active scroll section. This is a bounded observed scenario, not a promise
of a particular frame rate across devices or every conversation. Evidence is
under `/tmp/bedrock-pilot-validation/usability-regression/scroll/`; the updated
input samples are in `usability-regression/after-fixes/performance/`.

## Historical paging experiments, superseded by continuous history

Bounded rendering initially introduced a separate usability regression: prepending an older page moved the passage being read. A single `ScrollViewProxy.scrollTo` lost its pixel offset, and SwiftUI ID-based scroll positioning did not preserve the non-lazy transcript's geometry reliably.

That version recorded native message geometry only when needed, prewarmed the bounded Markdown page off the main actor, and restored the message's offset through the native clip view. A real user scroll canceled preservation. Small per-thread snapshots retained the message ID, offset, and rendered range without retaining message views or attachment data. The current lazy transcript retains geometry-based restoration without the page limits or rendered-range state.

Actual 70 checks retained the exact vertical coordinate through:

- Initial paging from 32 to 64 rendered messages.
- Three more earlier-page operations, including removal of bottom pages at the 96-message cap.
- Two newer-page operations while removing old pages.
- Three consecutive Activity → Back round trips without another scroll.
- Resizing the window to 980×700, 1440×860, and back to 1240×780.

Two teardown orders have native regression coverage: AppKit removing a view, and SwiftUI dismantling its representable first. The second round trip had failed in 69 because a freshly restored controller had no retained checkpoint; 70 preserves that checkpoint and captures before unregistration.

Warm opening of the 1,000-message fixture on 70 took 0.477–0.489s including activation and accessibility polling. A complete graceful relaunch to visible saved history took 0.929s. These are different measurements from render-only or model-response latency.

## Reproduction

Compile [the public-API probe](../scripts/measure-ui-responsiveness.swift) as described in [Development](development.md#performance-checks). Preserve an old executable, use an isolated synthetic conversation, and record:

- Executable hash, build configuration, data directory, fixture size, window size, and appearance.
- Raw input/scroll samples, median, p95, maximum, failures, and elapsed time.
- Whether compilation or other CPU-intensive work was running.
- Functional checks after optimization: shortcuts, draft retention, model switching, search, tool details, and Settings lifecycle.

The UI suite also measures typing in an imported 1,000-message conversation and exercises scrolling and shortcuts. Hosted `.xcresult` timing and local probe timing are different measurements and must be reported separately.

## Validation status

Validation 62 used the original Validation bundle identifier and data folder. The old 50 app and pre-update data were preserved. All previously nonempty history files remained unchanged during replacement; two old empty history files were removed by the existing unused-chat cleanup.

On the updated app, the following were exercised:

- Light and Dark Settings: nine panes at two window sizes, with no horizontally clipped input controls; five close/reopen cycles; System appearance restored.
- Nova 2 Lite reply, in-chat switch to GPT-6 Astra with draft/context preservation, skill listing/loading, and a harmless shell command with exit code 0.
- A follow-up queued during the tool run, processed afterward with the remembered conversation marker.
- Tool output Find with a highlighted match, exact input/output copying, and sheet dismissal.

Validation 64 retains the same command observation fix. Toolbar buttons now have distinct button roles, names, identifiers, and actions; model search keeps its own identifier inside the popover. Actual sidebar clicks and ⌘B, Back and ⌘[, ⌘N/⌘D, ⌘F, ⌘K, outside-click/Escape search dismissal, Settings open/close, and model switching with a retained draft passed.

Further runtime checks on 64:

| Scenario | Observed result |
| --- | --- |
| Open the 1,000-message fixture after restart | 0.52 s including automation |
| Reopen the same fixture three times | 0.31–0.33 s including automation |
| Page into older history | 32 → 64 → 96 rendered messages; further paging stayed at 96 |
| Global content search | Found the oldest fixture passage; in-chat Find reported both matches |
| Paste 232,237 bytes of multilingual text | Attachment ready in 0.29 s; exact content survived editing and reopening |
| Paste text and two 4096×3072 PNGs | Both images and the text ready in 0.84 s |
| Quit and restore that draft | Text visible in 0.61 s; all three attachments ready in 1.00 s; model and edited text retained |
| Send that document and both images to Nova 2 Lite | Actual response returned the final document marker and image count 2 |
| Paste 104,115 bytes of HTML-only content | Attachment ready in 0.29 s; last of 2,000 paragraphs retained; script/style content removed |
| Open a 4096×3072 generated-image fixture four times | 0.39–0.61 s per opening; zoom/reset/close passed |
| Copy and save the image | Both outputs byte-for-byte identical to the original PNG |

These wall-clock interaction observations include input injection, accessibility queries, polling, and launch/activation overhead. They are separate from the lightweight typing probe and are not renderer frame-time measurements. All 28 pre-existing nonempty history files (178 messages) remained byte-for-byte unchanged.

Raw local evidence is under `/tmp/bedrock-pilot-validation/comparison-64/`. The remaining scenarios and exact validation boundaries are tracked in [PERFORMANCE_VALIDATION_MATRIX.md](quality/validation-matrix.md). Hosted Xcode UI tests, every model/region, and all settings/automation combinations are not established by this pass.

The 70, 71, and 73 measurements and interaction records use corresponding
`comparison-70`, `comparison-71`, and `comparison-73` directories. On 73,
toolbar labels and disabled Back state were checked after chat changes,
Settings, popovers, and sidebar toggling. Native toolbar hit targets are
40×38 points; the visible glyphs remain 14 points.

The release preparation build also split `MainView`'s large SwiftUI expression
for the stable Xcode compiler and removed an unused Vapor dependency. A targeted
check of that exact optimized executable (`D4EE1420-D60F-3D1C-95A1-58FACDD07980`)
used the same 1,000-message fixture, 1240×780 window and Light appearance.
Typing measured median 10.52ms, p95 14.13ms and maximum 35.59ms. The scroll
probe completed in 5.985s with no failures. These are consistency checks
after the build changes, not evidence of an additional speedup.

Command-B, K, F, comma, W and Back remained functional. Three images and the
complete pasted-text attachment restored after replacement of the executable.
Raw records are in
`/tmp/bedrock-pilot-validation/release-preflight/final-native-smoke/`.
