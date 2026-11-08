A small fix release that prepares Stardew Valley for HaikuOS for packaging as a Haiku package (`.hpkg`) for HaikuPorts / HaikuDepot.

**This package contains no game files.** You need to own Stardew Valley (Steam, or the Windows build from GOG).

## Upgrade

Unzip `StardewValley-haiku.zip` over your existing `StardewValley` folder; your game files, saves, mods and controller mappings stay as they are. Nothing changes for the zip install.

## Changes since 0.1.1

- **Package installs keep their data in `~/config/settings/StardewValley`.** 0.1.1 used `~/config/data`, which on Haiku is a read-only view of installed packages, so an installed package couldn't start. Zip installs still keep everything in their own folder.
- **Clear error instead of silence:** if the launcher can't write to its data folder, it now says so in an alert. Started from the Deskbar, it previously exited without any message.
- **Smaller package:** the Linux-only launchers that came with the patcher and SMAPI are no longer included; on Haiku both run through .NET.
- **HaikuPorter recipe** in `haiku/haikuports/`, with a guide in `docs/Packaging.md`.

## Known issues

Unchanged from 0.1.1:

- Haiku media kit race: the game can occasionally crash as audio starts (`BTimeSource::GetTime`). The launcher offers to restart the media services and retry.
- Controllers must be connected before starting the game; Haiku's SDL backend has no hotplug.
- Some XInput controllers can switch themselves off with Haiku's stock `usb_hid` driver.
- SMAPI mods and direct-IP multiplayer are still unconfirmed on real hardware.

Please report problems with your `VERSION`, Haiku revision, `log.txt` and `logs/exceptions.txt`: https://github.com/Techniix/Stardew-Valley_HaikuOS/issues

Stardew Valley is © ConcernedApe LLC. This project is unofficial and not affiliated with ConcernedApe.
