# Performance

Bedrock renders the full conversation through an AppKit scroll document.
Lightweight positions cover the history; message views are created near the
viewport and released as they move away. There are no manual loading pages.

## Streaming and scrolling

Version 2.0.1 addresses four causes of overlapping or flickering responses:

- A message's measured height updates its parent row, including changes after
  Markdown or images finish loading.
- Message content remains top-aligned and clipped to its row while asynchronous
  layout updates are pending.
- Width changes retain previous row heights as estimates until remeasurement,
  preventing scrollbar changes from repeatedly recreating long responses.
- Completing a stream retains the final text until the saved conversation
  replaces it. Response actions reserve their height throughout the transition.

Unchanged visible messages reuse their views. Short native responses update
only changed text; long Markdown responses update existing WebKit nodes.
Height reports are coalesced and checked against the current width. The brief
opacity effect on new text respects Reduce Motion and never animates layout
or overrides manual scrolling.

## Release measurements

Measurements below were taken on macOS 26.6.2 using an optimized Release app,
a 1240×780 window, Light appearance and a synthetic 1,000-message conversation.
No compilation, inference or recording ran during the input probes.

| Probe | Events | Median | p95 | Maximum | Failed queries |
| --- | ---: | ---: | ---: | ---: | ---: |
| First scroll after opening the history | 360 | 0.43 ms | 3.18 ms | 17.25 ms | 0 |
| Warm scroll | 360 | 0.28 ms | 0.96 ms | 18.02 ms | 0 |
| Typing | 61 | 6.15 ms | 11.03 ms | 38.38 ms | 0 |

Typing measures input-to-accessibility-text latency. Scrolling measures small
accessibility queries during wheel input. These are individual observations on
one Mac, not display frame times, model-response latency or guarantees for every
device. The preceding candidate's first-scroll maximum was 94.08 ms.

Separate live AWS checks exercised streaming alongside scrolling, resizing,
sidebar changes and draft editing:

| Scenario | Observation |
| --- | --- |
| GPT-6 Astra, Low effort | A 16,556-character response completed in 86.95 seconds. Across 205 samples, including completion, the reading anchor moved 0 points while the response grew 6,190 points. Its height never decreased; the draft and final text were retained. |
| Nova 2 Lite with existing image/document history | A 15,987-character response completed in 45.00 seconds. Window resizing, sidebar toggling and typing continued during the request. |
| Older image preservation | All four stored image checksums remained unchanged after successful retransmission. |

Network timing includes provider inference and is separate from UI performance.
These live scenarios do not establish every model, region or attachment
combination. Automated coverage and its boundaries are described in the
[CI scenario map](testing.md).

## Regression coverage

Native tests cover 10,000-message indexing with bounded live views, independently
growing and shrinking messages, width-driven reflow, reading-position
preservation and following the bottom. UI tests exercise the actual scroll
surface, long streaming replies, mixed attachments, model switching, image
previews and Light/Dark appearances.

The tests assert message boundaries and reading position, in addition to
checking that the app responds. Draft-observation tests verify that typing does
not republish the entire app state. Full main CI and release validation remain
separate gates from targeted local measurements.

## Reproduce a measurement

Follow [Development](development.md#performance-checks) to build an optimized app
with isolated data. Compile `scripts/measure-ui-responsiveness.swift`, open a
synthetic conversation and use the same fixture, window, appearance and display
for each candidate.

Record:

- Tested commit, build configuration, macOS version and hardware.
- Fixture size, window dimensions, appearance, and cold or warm cache state.
- Raw samples, median, p95, maximum, failed queries and total elapsed time.
- Whether compilation or other CPU-intensive work ran during measurement.
- Functional results for scrolling, shortcuts, draft retention and attachments.

Avoid full accessibility-tree snapshots during timing; resolving thousands of
labels can itself consume substantial main-thread time. Keep raw local records
in `artifacts/`. Public reports should contain reproducible methods and
sanitized results, without personal paths, account identifiers or conversation
content.
