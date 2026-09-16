# Screenshots and demo

README media should show the running app with dedicated demonstration data.
Keep personal conversations, account identifiers, credentials, and unrelated
desktop windows out of the capture.

## Current capture

Recorded September 16, 2026 from the optimized 2.0.0 Release app on macOS
26.6.2. The separate **Bedrock Showcase** app uses demonstration data and
contains the current image-preview, Quick Access, and connection-isolation
corrections. It is a normal Release build with AWS connections enabled.

The conversation starts with a real Nova 2 Lite response developing a glass
cabin beside an alpine lake under the northern lights. During the recording,
the same conversation switches to **Stable Image Ultra 1.0**
(`stability.stable-image-ultra-v1:1`) and sends Nova's image prompt. The result
is generated through the app's real AWS connection, then opened and enlarged
in the image preview. The image request took approximately **9.22 seconds** in
this recording; its entire wait is included.

| Time | Interaction |
| --- | --- |
| 0–3s | Read Nova's concept and image prompt |
| 3–6s | Find and select Stable Image Ultra in the composer |
| 7–9s | Send the image prompt in the same conversation |
| 9–18s | Wait for the real image generation request |
| 18–21s | See the generated aurora landscape in the conversation |
| 21–30s | Open the image, zoom in, and fit the complete composition |
| 30–35s | Return to the image and composer |

The window is captured at its native Retina resolution, **2480×1560**.
Exports add 64 pixels of space on each side, producing **2608×1688** media
without upscaling the app. The original macOS window mask removes desktop
pixels outside the rounded corners. A restrained shadow and neutral canvas
give every screenshot the same framing, with a matching dark canvas for
Dark appearance.

| Asset | Resolution | Format and timing | Size |
| --- | --- | --- | --- |
| Main animation | 2608×1688 | Adaptive WebP, up to 20fps, 35 seconds | 11.4MB |
| Downloadable tour | 2608×1688 | H.264 MP4, 60fps, 35 seconds | 5.0MB |
| Legacy animation fallback | 1600×1036 | GIF, 15fps, 35 seconds | 6.5MB |
| Main screenshots | 2608×1688 | Lossless WebP and PNG | 0.6–0.9MB |
| Settings screenshots | 1828×1528 | Lossless WebP | 0.04–0.06MB |

The main README picture prefers WebP and uses the still image when
`prefers-reduced-motion` is enabled. Only unused trailing footage was trimmed
from the screen recording. Playback speed and inference timing are unchanged;
the video contains no audio. Static screenshots follow the viewer's Light or
Dark preference. Resolutions, sizes, and checksums are recorded in
[`assets/media.json`](assets/media.json).

## Reproduce the demonstration

1. Build the Release app using [Development](development.md).
2. Start a separate preview with its own bundle identifier and data:

   ```sh
   BEDROCK_PREVIEW_ROOT=/tmp/bedrock-readme-capture \
   BEDROCK_PREVIEW_NAME="Bedrock Showcase" \
   BEDROCK_PREVIEW_BUNDLE_IDENTIFIER=local.bedrock.ReadmeCapture \
     scripts/run-preview.sh \
     ".build/xcode/Build/Products/Release/Amazon Bedrock.app"
   ```

3. Configure an AWS connection in this preview. Set the window to 1240×780
   points, keep the sidebar expanded at 240 points, and choose Light appearance.
4. Choose Nova 2 Lite and send:

   > Imagine a quiet glass cabin beside an alpine lake under the northern lights. Give me a short concept and a vivid image prompt, in about 60 words.

   Review the real answer before recording. A live model response varies. The
   image prompt returned in this capture was:

   > Moonlight glints off the glassy cabin, reflecting shimmering greens and purples of the northern lights across the still lake; snow-capped peaks loom silently in the distance, while a warm amber glow spills from the cabin's hearth, inviting quiet contemplation.

5. Set the image response's aspect ratio to **16:9**. Start the recording with
   Nova's concept visible. Open the model picker, search for Stable Image Ultra,
   select it, and send the image prompt. Wait for the actual request to finish.
   Open the generated image, zoom in, choose Fit, and return to the conversation.
   Keep the complete request wait and original playback speed.
6. Capture the generated image conversation in Light and Dark, and Settings →
   Skills in both appearances. The separate tool-output screenshot documents an
   actual earlier tool call from the same Release build; it is not part of the
   main demonstration. Save complete window PNGs with transparent corners and
   without the system's outer shadow (`screencapture -o`).
7. Record the fixed app rectangle at the display's native resolution, without
   microphone audio. Keep the window's position and size unchanged. A screen-area
   capture avoids the floating recording control that can appear over a
   window-targeted movie.

## Export media

The export command requires Pillow, ffmpeg, and the WebP command-line tools.
These are authoring tools; the app and CI documentation checks do not depend
on them.

```sh
brew install ffmpeg webp
python3 -m venv .build/media-tools
.build/media-tools/bin/python -m pip install Pillow==12.3.0
```

Put these actual captures in one folder:

```text
main-light.png
main-dark.png
settings-light.png
settings-dark.png
tool-details.png
demo-original.mov
```

The movie and `main-light.png` must have identical native dimensions. Then run:

```sh
.build/media-tools/bin/python scripts/export-readme-media.py \
  --capture /tmp/bedrock-readme-capture/capture \
  --output docs/assets
python3 scripts/validate-documentation.py
```

The exporter preserves the native window geometry, removes one Retina pixel
of edge contamination, and applies consistent padding and shadow. The MP4
uses progressive playback. The animated WebP combines lossless and quality-94
frames to keep text legible while reducing the weight of photographic frames.
Static WebP screenshots remain lossless. The GIF is a compatibility fallback.
This presentation recording is not a performance benchmark.

Inspect the first, intermediate, and final frames after conversion. Check
text, controls, popovers, corner masks, and both appearances. The documentation
CI check verifies local links, actual image/movie dimensions, native framing,
checksums, and the main animation's duration. Do not publish if the capture
includes another window or exposes personal data.
