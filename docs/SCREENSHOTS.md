# Screenshots and demo

README media should show the running app with dedicated demonstration data.
Keep personal conversations, account identifiers, credentials, and unrelated
desktop windows out of the capture.

## Reproduce the demonstration

1. Build the Release app using [Development](DEVELOPMENT.md).
2. Start a separate preview with its own bundle identifier and data:

   ```sh
   BEDROCK_PREVIEW_ROOT=/tmp/bedrock-readme-capture \
   BEDROCK_PREVIEW_BUNDLE_IDENTIFIER=local.bedrock.ReadmeCapture \
     scripts/run-workbench-preview.sh \
     ".build/xcode/Build/Products/Release/Amazon Bedrock.app"
   ```

3. Configure an AWS connection in this preview. Set the window to 1240×780
   points, keep the sidebar expanded at 240 points, and choose Light appearance.
4. Save this intentionally incomplete function as `Median.swift`, then attach
   it through the composer's file button:

   ```swift
   func median(_ numbers: [Double]) -> Double {
       let sorted = numbers.sorted()
       return sorted[sorted.count / 2]
   }
   ```

5. Send:

   > Use the code-review skill to review this Swift function for empty and even-length inputs. Show a concise fix and two example calls.

   A live model response varies. Review its output before using any proposed
   code. For the short implementation shown in the current capture, the
   follow-up asks the model to return `nil` for empty input and provide two
   assertions.
6. Record actual model selection, centered global search, sidebar navigation,
   and tool inspection. Changing the selected model does not itself send a
   request. Keep the original recording timing.
7. Capture the same conversation in Light and Dark, plus a Settings view.
   Use the macOS Screenshot tool to capture only the app window. Record only
   the app's screen area, without microphone audio.

## Export media

The PNG is a full-resolution static fallback. WebP files are used for the
appearance-aware screenshot. The animated GIF is reduced to 12 frames per
second and 1120 pixels wide for README loading; it is not a frame-rate benchmark.

```sh
mkdir -p assets/readme
cp /tmp/bedrock-main-light.png assets/preview.png
cwebp -q 88 -resize 1440 0 /tmp/bedrock-main-light.png \
  -o assets/readme/main-light.webp
cwebp -q 88 -resize 1440 0 /tmp/bedrock-main-dark.png \
  -o assets/readme/main-dark.webp

ffmpeg -i /tmp/bedrock-demo.mov \
  -filter_complex \
  "[0:v]fps=12,scale=1120:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle[out]" \
  -map "[out]" -loop 0 assets/preview.gif
```

Inspect the first, intermediate, and final frames after conversion. Check
that menus, text, controls, and both themes remain readable, that the static
fallback exists, and that every README media path resolves.
