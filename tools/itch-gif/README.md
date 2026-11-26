# Record a gameplay GIF

Record a looping GIF of Mini Mage for the itch.io mobile page. The file is the level only. The script clicks **Start Game** and does not save the menu.

The player walks south past the crates, north behind the sentries, east along the wall, and back west. The sentry cones stay in view. The player stays outside them.

You need Godot 4.7, ffmpeg, and a display. The window matches `mm-verify`. It is 960×540, with renderer `gl_compatibility` and audio driver Dummy.

## Record the GIF

Run this from the repo root.

```
tools/itch-gif/capture.sh
```

With no path, the script writes `tools/itch-gif/menu-to-stealth.gif`. That file is committed.

`capture.sh` imports the project when `.godot/uid_cache.bin` is missing. It then runs `tools/itch-gif/capture.gd`, which saves a PNG every 6 frames after the level loads. ffmpeg scales those frames to 480×270 with nearest-neighbor filtering and writes a GIF that loops.

Set `GODOT` when the binary is not on `PATH` and not at `$HOME/.local/godot/Godot_v4.7-stable_linux.x86_64`. Set `ITCH_GIF_FRAMES` to choose the PNG directory. The default directory is `/tmp/itch-gif-frames`.

The route is the `BEATS` array in `tools/itch-gif/capture.gd`. A run that follows that array starts the player at `(-464, -24)` and ends near `(-436, -74)`. Sentry alertness stays under 0.11.

A checked run wrote 59 frames at 10 fps. The clip is 5.9 seconds and 480×270. That file is 1331788 bytes. Every frame has a player in the level. A later run can differ by a few hundred bytes, because the sentries are still on patrol.
