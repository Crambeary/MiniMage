# Record a gameplay GIF

Record a looping GIF of Mini Mage for the itch.io mobile page. The clip plays the real menu, clicks **Start Game**, walks south past the crates, walks east under a sentry, and walks back west.

You need Godot 4.7, ffmpeg, and a display. The window matches `mm-verify`. It is 960×540, with renderer `gl_compatibility` and audio driver Dummy.

## Record the GIF

Run this from the repo root.

```
tools/itch-gif/capture.sh /path/to/menu-to-stealth.gif
```

`capture.sh` imports the project when `.godot/uid_cache.bin` is missing. It then runs `tools/itch-gif/capture.gd`, which saves a PNG every 6 frames. ffmpeg scales those frames to 480×270 with nearest-neighbor filtering and writes a GIF that loops.

Set `GODOT` when the binary is not on `PATH` and not at `$HOME/.local/godot/Godot_v4.7-stable_linux.x86_64`. Set `ITCH_GIF_FRAMES` to choose the PNG directory. The default directory is `/tmp/itch-gif-frames`.

The route is the `BEATS` array in `tools/itch-gif/capture.gd`. A run that follows that array leaves the player near `(-362, 16)` after starting at `(-464, -24)`.

A checked run wrote 51 frames at 10 fps. The clip is 5.1 seconds and 480×270. That file is 714736 bytes. A later run can differ by a few hundred bytes, because the sentry is still on its patrol.
