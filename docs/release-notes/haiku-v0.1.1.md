A small polish release for Stardew Valley for HaikuOS: startup is now clean, with no flashing windows.

**This package contains no game files.** You need to own Stardew Valley (Steam, or the Windows build from GOG).

## Upgrade

Unzip `StardewValley-haiku.zip` over your existing `StardewValley` folder; your game files, saves, mods and controller mappings stay as they are. New installs follow the steps in the README (`./setup.sh`).

## Changes since 0.1.0

- **Clean startup.** The game used to open a white fullscreen window, then flicker through two windowed sizes before switching to fullscreen. The window now stays hidden until the game has applied its saved size and mode, and appears once. Haiku's SDL2 backend shows new windows even when they're created hidden, so the window is hidden again right after it's created.
- **"Please wait" notification.** While the window is hidden, a Haiku notification says *Launching Stardew Valley: please wait...* and disappears as soon as the game is on screen. `SDV_NO_LAUNCH_NOTICE=1` turns it off; `MONOGAME_SHOW_WINDOW_EARLY=1` restores the old startup if the new one causes trouble.
- **Groundwork for a Haiku package.** When installed read-only (as a `.hpkg` would be), the scripts keep game files, mods, logs and settings in the user data folder instead of the install folder. The zip release works exactly as before.
- **Build fix:** `build-managed.sh` re-applies the whole MonoGame patch series from the pinned files, so patches that touch the same file apply reliably.

## Known issues

Unchanged from 0.1.0:

- Haiku media kit race: the game can occasionally crash as audio starts (`BTimeSource::GetTime`). The launcher offers to restart the media services and retry.
- Controllers must be connected before starting the game; Haiku's SDL backend has no hotplug.
- Some XInput controllers can switch themselves off with Haiku's stock `usb_hid` driver.
- SMAPI mods and direct-IP multiplayer are still unconfirmed on real hardware.

Please report problems with your `VERSION`, Haiku revision, `log.txt` and `logs/exceptions.txt`: https://github.com/Techniix/Stardew-Valley_HaikuOS/issues

Stardew Valley is © ConcernedApe LLC. This project is unofficial and not affiliated with ConcernedApe.
