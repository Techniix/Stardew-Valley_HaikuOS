# Stardew Valley for HaikuOS

Run Stardew Valley 1.6 natively on [Haiku](https://www.haiku-os.org/) (x86_64)
with the Haiku port of .NET. This is a launcher and compatibility kit: **it
contains no game files**. You need your own copy of Stardew Valley.

> Status: **experimental, not yet tested on real hardware.** Bug reports with
> `log.txt` attached are very welcome.

## How it works

Stardew Valley is a .NET 6 game built on MonoGame. Its game code is
platform-neutral .NET, so it doesn't need to be ported. What it runs *on* does:

- **.NET runtime:** [trungnt2910/dotnet-builds](https://github.com/trungnt2910/dotnet-builds)
  (9.0 or newer; `setup.sh` installs 10). Haiku has no .NET 6, so the game
  runs on the newest installed runtime via `rollForward: LatestMajor`.
- **MonoGame:** the game's bundled `MonoGame.Framework.dll` is replaced with a
  build of [Producdevity's Stardew-compatible MonoGame fork](https://github.com/Producdevity/MonoGame/tree/portmaster-stardew-mainline)
  plus Haiku patches ([`patches/monogame/`](patches/monogame/)).
- **Game patcher:** `MainlineGameDataPatcher` rewrites the game's
  `deps.json`/`runtimeconfig.json` for Haiku, removes Windows-only native
  files and applies a few IL fixes to `Stardew Valley.dll`. It runs on your
  machine against your own copy, once per game update.
- **Native shims:** tiny C libraries standing in for the Steam API and Windows
  `user32`/`imm32` calls, plus an SDL2 clipboard bridge. They're built on Haiku
  by `build-native.sh`.
- **System libraries:** SDL2 and OpenAL from HaikuPorts, OpenGL through Mesa.
- **Game download:** `get-game-steam.sh` fetches your own copy straight from
  Steam with [DepotDownloader](https://github.com/SteamRE/DepotDownloader),
  which itself runs on .NET for Haiku. No Windows or Linux machine needed.

## How this differs from other ports

### vs. the Haiku forum method ([Stardew Valley on Haiku](https://discuss.haiku-os.org/t/stardew-valley-on-haiku/19174), May 2026)

That thread showed the game *can* run on Haiku. It's a manual procedure, and
this project aims to make it repeatable and robust:

| | Forum method | This port |
|---|---|---|
| MonoGame on Haiku | Hex-edits the `libSystem.dylib` path inside the game's `MonoGame.Framework.dll` | Source-level fix: MonoGame detects Haiku as its own OS, loads `dlopen` from `libroot.so`, and uses the correct SDL2/OpenAL names |
| System changes | A `/usr/lib` symlink that's lost on every reboot | None: everything stays in the game folder |
| Game build | GOG | Windows Steam or GOG (1.6 mainline) |
| Steam / Windows natives | Not handled | Stub/shim libraries |
| Audio | Bundled MonoGame audio, unconfirmed | Fork with OpenAL fixes (loop-state reset, effect filtering, dedicated audio worker) |
| Mods (SMAPI) | No | Bundled SMAPI, turned on automatically when `Mods/` has mods (see [Mods](#mods-smapi)) |
| Source | Not published | This repository, MIT |
| Getting the game | Copy files over from another machine | Download from Steam directly on Haiku (`get-game-steam.sh`), or copy |
| Install | Follow forum steps | `setup.sh` installs packages, .NET, shims, game and Deskbar entry; `.hpkg` planned |

### vs. the PortMaster port it's based on ([Producdevity/portmaster-stardew-valley-mainline](https://github.com/Producdevity/portmaster-stardew-valley-mainline))

This repo is a fork of that project and keeps its full history. The upstream
PortMaster build still works (see [`docs/PortMaster.md`](docs/PortMaster.md)).
The Haiku differences:

- **Target:** Haiku x86_64 desktop instead of aarch64 Linux handhelds.
- **Runtime:** system .NET 8+ for Haiku with roll-forward, instead of a bundled
  Microsoft .NET 6 runtime (none exists for Haiku).
- **Desktop profile:** the patcher gained a `--profile desktop` mode that keeps
  vanilla window modes, UI scale, zoom and mouse input. The handheld rewrites
  (forced borderless fixed resolution, display-size scaling, synthesised
  pointer) are skipped. MonoGame mouse motion is re-enabled on Haiku.
- **Configurable patcher:** new `--runtime-target`, `--framework-version` and
  `--roll-forward` options. PortMaster defaults are unchanged.
- **No GL4ES or PortMaster tooling:** native OpenGL through Haiku's Mesa, no
  gptokeyb.
- **Setup and game download on the device:** `setup.sh` and
  `get-game-steam.sh` replace copying files from a PC.
- **Build fix:** `bootstrap-monogame-thirdparty.sh` now fetches the pinned
  NVorbis commit directly (a shallow clone couldn't check it out).

## Install (Haiku)

Unzip the release (or build it, below), then in Terminal:

```sh
./setup.sh
```

`setup.sh` does everything, skipping steps that are already done:

1. installs SDL2, OpenAL, gcc and the .NET dependencies with `pkgman`
2. installs .NET 10 for Haiku into `./dotnet`, unless .NET 9+ is already installed
3. builds the native shims
4. offers to download Stardew Valley from Steam. You log in with your own
   account (username + password + Steam Guard, or a QR code via `--qr`). Your
   password and Steam Guard code go straight to DepotDownloader; these scripts
   never see or store them.
5. adds Stardew Valley to the Deskbar Applications menu

Then launch from the Deskbar or with `./StardewValley.sh`. Run
`./get-game-steam.sh` again to update the game.

GOG or already-copied files: put your Stardew Valley folder's contents (with
`Stardew Valley.dll`) into `gamedata/` and run `./setup.sh --no-game`.
See [`haiku/INSTALL.txt`](haiku/INSTALL.txt).

## Mods (SMAPI)

### How it works in this port

[SMAPI](https://smapi.io/) is the standard Stardew Valley mod loader. Normally
you run its installer, which copies files into the game folder and replaces the
launcher. That installer doesn't support Haiku, so this port handles it itself:

1. **SMAPI is bundled.** The package contains SMAPI 4.5.2 (LGPL-3.0) in
   `tools/SMAPIBundle/`, taken from the official installer's Linux payload.
   Haiku is a Unix system, and SMAPI treats it as Linux.
2. **Mode is chosen at each launch.** `StardewValley.sh` looks in `Mods/`. If it
   contains any mod besides SMAPI's own *Console Commands* and *Save Backup*,
   the game starts through SMAPI. Otherwise it starts vanilla. You never run
   an installer and never switch launchers.
3. **The patcher installs SMAPI into the game.** In SMAPI mode, the Haiku
   patcher copies SMAPI into `gamedata/`, points SMAPI's
   `deps.json`/`runtimeconfig.json` at the Haiku .NET runtime, and aligns the
   game's assembly versions with what SMAPI expects. It also fixes up mod
   DLLs in `Mods/` (architecture flags) so they load on this runtime.
4. **Re-patching is automatic.** The launcher re-runs the patcher whenever
   you switch between vanilla and SMAPI, update the game or .NET, or add or
   change anything in `Mods/`.
5. **SMAPI runs inside the launcher's shell.** Its console output goes to the
   Terminal and to `log.txt`, not a separate terminal window. SMAPI also keeps
   its usual log in `~/.config/StardewValley/ErrorLogs/SMAPI-latest.txt`.
   [smapi.io/log](https://smapi.io/log) can parse it.
6. **The patched MonoGame stays in place.** SMAPI loads the same
   Haiku-patched `MonoGame.Framework.dll` as vanilla mode.

What works with what:

| Mod type | Expected to work? |
|---|---|
| Content Patcher packs, Json Assets, other content-only mods | Yes, they're pure data |
| C# SMAPI mods (most mods on Nexus) | Usually: they're platform-neutral .NET |
| Mods that use Harmony to patch game code | Untested on Haiku. See note below |
| Mods that ship Windows/Linux native libraries (`.dll`/`.so` with C code) | No |
| Mods that depend on Steam features or on Stardew's exact Steam MonoGame build | May fail |

> **Harmony on Haiku is the biggest unknown.** Harmony rewrites game methods
> while the game is running, which relies on low-level, OS-specific tricks
> (MonoMod). It works on Linux, macOS and Windows; on Haiku it hasn't been
> tested yet. SMAPI itself uses Harmony, so if SMAPI fails to start on
> Haiku, this is the likely cause. Please report it with your SMAPI log.

### Setting up mods

1. **Run the game once in vanilla mode** so the base patching is done:
   `./StardewValley.sh`
2. **Download mods** from [Nexus Mods](https://www.nexusmods.com/stardewvalley)
   or [ModDrop](https://www.moddrop.com/stardew-valley). Pick versions made for
   Stardew Valley 1.6 and SMAPI 4.x. Get the main download, not the
   Windows/Mac "installer" variants.
3. **Unzip each mod into `Mods/`** in the port folder (not into `gamedata/`).
   Each mod needs its own folder containing a `manifest.json`:
   ```
   StardewValley/
   └── Mods/
       ├── ContentPatcher/
       │   ├── manifest.json
       │   └── ContentPatcher.dll
       └── [CP] Some Content Pack/
           ├── manifest.json
           └── content.json
   ```
   Folders can be nested one level for organisation; SMAPI searches subfolders.
4. **Install dependencies.** Many mods need a framework mod (Content Patcher,
   SpaceCore, Generic Mod Config Menu...). The mod's page lists them; SMAPI
   also names missing ones in its log.
5. **Launch normally** (`./StardewValley.sh` or the Deskbar entry). The first
   SMAPI launch takes a little longer while the game is re-patched. You should
   see the SMAPI banner and the loaded mods in the Terminal, and a mod count on
   the title screen.

Useful switches:

```sh
SDV_VANILLA=1 ./StardewValley.sh       # play unmodded without removing Mods/
SDV_FORCE_SMAPI=1 ./StardewValley.sh   # start SMAPI even with no extra mods
SDV_FORCE_PATCH=1 ./StardewValley.sh   # redo all patching
```

**Removing mods:** delete their folders from `Mods/`. Once only SMAPI's
built-in mods are left, the launcher goes back to vanilla automatically.

**Saves:** vanilla and SMAPI share the same save folder
(`~/.config/StardewValley/Saves`). SMAPI's *Save Backup* mod zips your saves into
`Mods/SaveBackup/backups` on each launch. Still, back up saves yourself before
trying large mods.

**Troubleshooting:**
- *A mod doesn't load:* check the SMAPI log for "skipped mods"; usually it's a
  missing dependency or a version mismatch.
- *SMAPI crashes on startup:* run with `SDV_VANILLA=1` to confirm the base game
  works, then attach `log.txt` and `SMAPI-latest.txt` to an issue.
- *"Native library not found" from a mod:* that mod ships platform-specific
  native code and won't work on Haiku.

## Build

The managed parts are platform-neutral and can be built on Linux (or on Haiku
with the .NET SDK):

```sh
git clone https://github.com/Techniix/Stardew-Valley_HaikuOS
git clone -b portmaster-stardew-mainline https://github.com/Producdevity/MonoGame
cd Stardew-Valley_HaikuOS
./haiku/build-managed.sh        # -> haiku/out/StardewValley-haiku.zip
```

Unzip on Haiku and run `./build-native.sh` there.

## Roadmap

- [ ] First boot on real hardware: title screen, audio, input
- [ ] Confirm SMAPI/Harmony on real Haiku hardware
- [ ] `.hpkg` with icon and Deskbar entry, HaikuDepot submission
- [ ] GOG downloader (e.g. lgogdownloader) alongside Steam
- [ ] Gamepad testing

## Credits & license

- Original PortMaster port, MonoGame fork, patcher and shims:
  [Producdevity](https://github.com/Producdevity)
- .NET for Haiku: [trungnt2910](https://github.com/trungnt2910)
- Haiku port: Dalton Singleton ([@Techniix](https://github.com/Techniix))

MIT, see [`LICENSE`](LICENSE). Third-party components and the game-files policy
are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Stardew Valley is © ConcernedApe LLC. This project is unofficial and not
affiliated with ConcernedApe.
