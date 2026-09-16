#!/usr/bin/env python3
"""Export Retina README media with clean native window edges and consistent framing.

Requires Pillow, ffmpeg, and img2webp. Input PNGs are actual macOS window captures
without shadows; the movie records the same rectangle at its native resolution.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from PIL import Image, ImageFilter


def native_mask(image):
    alpha = image.getchannel("A")
    if alpha.getextrema() != (0, 255):
        raise ValueError("Capture the entire macOS window as an alpha PNG, without its shadow.")
    # Remove one Retina pixel of desktop contamination at the movie's edge.
    # No text, controls, or other content inside the window is changed.
    return alpha.filter(ImageFilter.MinFilter(3))


def backdrop(mask, padding, dark):
    background = (18, 20, 24) if dark else (247, 248, 250)
    size = (mask.width + 2 * padding, mask.height + 2 * padding)
    canvas = Image.new("RGBA", size, (*background, 255))
    shadow = Image.new("L", size)
    shadow.paste(mask, (padding, padding + 12))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22)).point(lambda value: round(value * (0.30 if dark else 0.14)))
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.putalpha(shadow)
    return Image.alpha_composite(canvas, layer)


def compose(image, padding, dark=False):
    mask = native_mask(image)
    canvas = backdrop(mask, padding, dark)
    window = image.copy()
    window.putalpha(mask)
    canvas.alpha_composite(window, (padding, padding))
    return canvas.convert("RGB")


def probe(path):
    result = subprocess.run([
        "ffprobe", "-v", "error", "-show_entries",
        "stream=width,height,codec_name,r_frame_rate:format=duration", "-of", "json", str(path)
    ], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=Path("docs/assets"))
    parser.add_argument("--padding", type=int, default=64, help="Retina pixels around the complete window")
    args = parser.parse_args()
    for executable in ("ffmpeg", "ffprobe", "img2webp"):
        if not shutil.which(executable):
            parser.error(f"{executable} is required. Install ffmpeg and webp before exporting.")
    capture, output = args.capture.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    main_image = Image.open(capture / "main-light.png").convert("RGBA")
    if main_image.width < 2240 or main_image.width % 2 or main_image.height % 2:
        parser.error("Use a native Retina window capture at least 2240 pixels wide, with even dimensions.")
    if args.padding < 32 or args.padding % 2:
        parser.error("Use an even padding of at least 32 pixels.")
    movie = capture / "demo-original.mov"
    source_video = probe(movie)
    dimensions = source_video["streams"][0]
    if (dimensions["width"], dimensions["height"]) != main_image.size:
        parser.error("The movie and window PNG must have the same native pixel dimensions.")

    stills = {
        "main-light": "chat-light", "main-dark": "chat-dark",
        "settings-light": "settings-light", "settings-dark": "settings-dark",
        "tool-details": "tool-details"
    }
    for source, destination in stills.items():
        image = Image.open(capture / f"{source}.png").convert("RGBA")
        composed = compose(image, args.padding, dark=source.endswith("-dark"))
        composed.save(output / f"{destination}.webp", lossless=True, method=6)
        if source == "main-light":
            composed.save(output / "hero.png", optimize=True)

    with tempfile.TemporaryDirectory(prefix="bedrock-readme-media-") as temporary:
        work = Path(temporary)
        mask = native_mask(main_image)
        mask.save(work / "window-mask.png")
        backdrop(mask, args.padding, False).convert("RGB").save(work / "backdrop.png")

        def encode(name, fps, options, tail="", destination=None):
            graph = (
                f"[0:v]fps={fps},setpts=PTS-STARTPTS,format=rgba[video];"
                "[video][1:v]alphamerge=shortest=1[window];"
                f"[2:v][window]overlay={args.padding}:{args.padding}:format=auto:shortest=1"
                + (f",{tail}" if tail else "") + "[out]"
            )
            command = [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-threads", "2",
                "-i", str(movie), "-loop", "1", "-framerate", str(fps), "-i", str(work / "window-mask.png"),
                "-loop", "1", "-framerate", str(fps), "-i", str(work / "backdrop.png"),
                "-filter_complex_threads", "2", "-filter_complex", graph,
                "-map", "[out]", "-an", "-threads", "2", *options, str(destination or output / name)
            ]
            result = subprocess.run(command, capture_output=True, text=True)
            if result.returncode:
                raise RuntimeError(f"{name}: {result.stderr[-3000:]}")
            print(f"Exported {name}", flush=True)

        def animated_webp():
            # Select lossless/lossy encoding per frame at high quality instead
            # of preserving every compression artifact in the source movie.
            # This keeps image-generation tours practical to load at Retina
            # resolution. Frames stay on disk instead of retaining hundreds
            # of uncompressed images in Python's memory.
            frames = work / "frames"
            frames.mkdir()
            encode("animation frames", 20, ["-c:v", "png", "-compression_level", "2"],
                   "format=rgb24", frames / "frame-%05d.png")
            command = [
                "img2webp", "-min_size", "-mixed", "-sharp_yuv",
                "-loop", "0", "-q", "94", "-m", "4", "-d", "50",
                *map(str, sorted(frames.glob("frame-*.png"))), "-o", str(output / "demo.webp")
            ]
            result = subprocess.run(command, capture_output=True, text=True)
            if result.returncode:
                raise RuntimeError(f"demo.webp: {result.stderr[-3000:]}")
            print("Exported demo.webp", flush=True)

        with ThreadPoolExecutor(max_workers=2) as workers:
            exports = [
                workers.submit(encode, "demo.mp4", 60, [
                    "-c:v", "libx264", "-preset", "slow", "-crf", "16",
                    "-pix_fmt", "yuv420p", "-movflags", "+faststart"
                ]),
                workers.submit(animated_webp),
            ]
            for export in exports:
                export.result()
        # Legacy fallback only. The README uses the full-resolution animated
        # WebP in current browsers; the downloadable movie keeps native pixels.
        encode("demo.gif", 15, ["-loop", "0"],
               "scale=1600:-2:flags=lanczos,split[a][b];"
               "[a]palettegen=stats_mode=diff[p];"
               "[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle")

    media = {}
    for name in ("hero.png", "chat-light.webp", "chat-dark.webp", "settings-light.webp",
                 "settings-dark.webp", "tool-details.webp", "demo.webp", "demo.gif", "demo.mp4"):
        path = output / name
        item = {"bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        if path.suffix == ".mp4":
            details = probe(path)
            item.update(details["streams"][0], duration=float(details["format"]["duration"]))
        else:
            with Image.open(path) as image:
                item.update(width=image.width, height=image.height)
        media[name] = item
    (output / "media.json").write_text(json.dumps({
        "nativeWindow": {"width": main_image.width, "height": main_image.height},
        "padding": args.padding, "movieTimingChanged": False,
        "animationEncoding": {"mode": "mixed", "quality": 94, "framesPerSecond": 20},
        "sourceDuration": float(source_video["format"]["duration"]),
        "files": media
    }, indent=2) + "\n")
    print(json.dumps(media, indent=2))


if __name__ == "__main__":
    main()
