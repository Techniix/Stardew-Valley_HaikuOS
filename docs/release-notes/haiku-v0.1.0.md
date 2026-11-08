First release of Stardew Valley for HaikuOS: Stardew Valley 1.6 running natively on Haiku x86_64 on the Haiku port of .NET.

**This package contains no game files.** You need to own Stardew Valley (Steam, or the Windows build from GOG).

## Install

1. Download `StardewValley-haiku.zip` below and unzip it wherever you like.
2. Open Terminal in the `StardewValley` folder and run `./setup.sh`.
3. Start the game from **Deskbar → Applications → Stardew Valley**, or with `./StardewValley.sh`.

`setup.sh` installs the needed HaikuPorts packages, installs .NET for Haiku, builds the native helpers, offers to download the game from Steam with your own account (or tells you where to copy it), and adds a Deskbar entry.

## What works

Confirmed on real hardware (Haiku hrev60368, Ryzen 5 7600X, RTX 5070):

- Setup, Steam download and game updates directly on Haiku
- The game with sound, from Terminal or the Deskbar, at a steady 60 fps
- Gamepads, after a one-time mapping with `./gamepad.sh`

Not confirmed yet: SMAPI mods (bundled and enabled automatically when `Mods/` contains mods) and direct-IP multiplayer. Steam friends and invite codes need the Steam client and aren't available on Haiku; see the README for direct-IP options.

## Highlights

- Haiku support in MonoGame at the source level (OS detection, `libroot.so`, SDL2/OpenAL), no system changes
- Steam download on Haiku via DepotDownloader, with a stall watchdog and a SteamKit2 workaround
- Fixes for Haiku's .NET: networking lookups that crashed multiplayer, and slow `Guid.NewGuid()` calls that froze the game when using tools
- Fewer `app_server` round trips per frame (cached window queries)
- Launcher help for a Haiku media kit crash: restart the media services or play without sound
- Built-in diagnostics: exception log, frame profiling (`SDV_PROFILE=1`) and CPU tracing with an on-device report (`SDV_TRACE=1`)

## Known issues

- Haiku media kit race: the game can occasionally crash as audio starts (`BTimeSource::GetTime`). The launcher offers to restart the media services and retry.
- Controllers must be connected before starting the game; Haiku's SDL backend has no hotplug.
- Some XInput controllers can switch themselves off with Haiku's stock `usb_hid` driver.

Please report problems with your `VERSION`, Haiku revision, `log.txt` and `logs/exceptions.txt`: https://github.com/Techniix/Stardew-Valley_HaikuOS/issues

Stardew Valley is © ConcernedApe LLC. This project is unofficial and not affiliated with ConcernedApe.
