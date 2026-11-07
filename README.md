# Stardew Valley for HaikuOS

Run Stardew Valley 1.6 natively on [Haiku](https://www.haiku-os.org/) x86_64,
with mod support, using the Haiku port of .NET. One script sets everything up
and can download your own copy of the game straight from Steam on Haiku.

**This project contains no game files.** You need to own Stardew Valley
(Steam, or the Windows build from GOG).

> **Status: early but working.** The game launches on real hardware
> (Haiku hrev60368, Ryzen 5 7600X). SMAPI/mods and gamepads are not
> confirmed yet. Bug reports with `log.txt` are very welcome.

- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [How this differs from other ports](#how-this-differs-from-other-ports)
- [Mods (SMAPI)](#mods-smapi)
- [Troubleshooting](#troubleshooting)
- [Building from source](#building-from-source)

## Quick start

1. Download `StardewValley-haiku.zip` from
   [Releases](https://github.com/Techniix/Stardew-Valley_HaikuOS/releases)
   (or [build it](#building-from-source)) and unzip it wherever you like.
2. Open **Terminal** in the unzipped `StardewValley` folder and run:
   ```sh
   ./setup.sh
   ```
3. Start the game from **Deskbar → Applications → Stardew Valley**, or with
   `./StardewValley.sh`.

`setup.sh` is safe to re-run; it skips what's already done:

| Step | What it does |
|---|---|
| 1. Packages | `pkgman install` SDL2, OpenAL, gcc and the libraries .NET needs |
| 2. .NET | Installs .NET 10 for Haiku ([trungnt2910/dotnet-builds](https://github.com/trungnt2910/dotnet-builds)) into `./dotnet`, unless .NET 9+ is already installed |
| 3. Native shims | Builds the small C libraries in `libs/` with gcc |
| 4. Game files | Offers to download the game from Steam (see below), or tells you where to copy it |
| 5. Deskbar | Adds a menu entry |

**Downloading from Steam** (`./get-game-steam.sh`, also run by `setup.sh`):
log in with username + password + Steam Guard, or `--qr` to scan a code with
the Steam app. Your password and Steam Guard code go straight to
[DepotDownloader](https://github.com/SteamRE/DepotDownloader); these scripts
never see or store them. With "remember", only DepotDownloader's login token is
kept, so later runs (game updates) don't ask again. Run it again any time to
update the game.

**Copying files instead (GOG, or an existing install):** copy the contents of
your Stardew Valley folder (the one with `Stardew Valley.dll`) into
`gamedata/` and run `./setup.sh --no-game`.

## How it works

Stardew Valley is a .NET 6 game built on MonoGame. Its game code is
platform-neutral .NET, so the game itself doesn't need porting. What it runs
*on* does:

- **.NET runtime:** .NET for Haiku, 9.0 or newer. Haiku has no .NET 6, so the
  game runs on the newest installed runtime via `rollForward: LatestMajor`.
- **MonoGame:** the game's `MonoGame.Framework.dll` is replaced with a build of
  [Producdevity's Stardew-compatible MonoGame fork](https://github.com/Producdevity/MonoGame/tree/portmaster-stardew-mainline)
  plus Haiku patches ([`patches/monogame/`](patches/monogame/)): MonoGame
  detects Haiku as its own OS, loads `dlopen` from `libroot.so`, and uses
  Haiku's SDL2 and OpenAL libraries.
- **Game patcher:** `MainlineGameDataPatcher` rewrites the game's
  `deps.json`/`runtimeconfig.json` for Haiku, removes the bundled Windows
  runtime and native files, and applies a few IL fixes to `Stardew Valley.dll`.
  It runs on your machine against your own copy, and again automatically after
  game, .NET or mod changes.
- **Native shims:** tiny C libraries standing in for the Steam API and the
  Windows `user32`/`imm32` calls, plus an SDL2 clipboard bridge.
- **System libraries:** SDL2 and OpenAL from HaikuPorts, OpenGL through Mesa.
- **Game download:** DepotDownloader runs on .NET for Haiku too. Two Haiku
  workarounds are built in:
  - Haiku's .NET can't list network adapters yet, which crashed SteamKit2 (the
    Steam library inside DepotDownloader) right after login. The script widens
    one `catch` in your local `SteamKit2.dll` so SteamKit uses its built-in
    fallback machine ID.
  - Downloads can stall silently. A watchdog restarts DepotDownloader (which
    resumes) when `steam-depot/` stops growing for 3 minutes.

Package layout:

```
StardewValley/
├── setup.sh              one-time setup
├── StardewValley.sh      launcher (vanilla or SMAPI, patches as needed)
├── get-game-steam.sh     download/update the game from Steam
├── build-native.sh       builds libs/ (called by setup.sh)
├── gamedata/             patched game files (yours)
├── steam-depot/          untouched Steam download (yours)
├── Mods/                 SMAPI mods
├── dotnet/               .NET for Haiku (if installed by setup.sh)
├── libs/                 native shims
├── overrides/ dlls/ tools/   Haiku MonoGame build, patcher, SMAPI bundle
├── licenses/             third-party licenses
├── log.txt               output of the last game run
└── VERSION               package version (include it in bug reports)
```

## How this differs from other ports

### vs. the Haiku forum method ([Stardew Valley on Haiku](https://discuss.haiku-os.org/t/stardew-valley-on-haiku/19174), May 2026)

That thread showed the game *can* run on Haiku. It's a manual procedure; this
project makes it repeatable and robust:

| | Forum method | This port |
|---|---|---|
| MonoGame on Haiku | Edits the `libSystem.dylib` path string inside the game's `MonoGame.Framework.dll` | Source-level fix in MonoGame (OS detection, `libroot.so`, SDL2/OpenAL names) |
| System changes | A `/usr/lib` symlink, lost on every reboot | None; everything stays in the package folder |
| Getting the game | Copy files from another machine | Download from Steam on Haiku, or copy |
| Game build | GOG | Steam or GOG (Windows build, 1.6) |
| Steam / Windows natives | Not handled | Stub/shim libraries |
| Audio | Bundled MonoGame audio | Fork with OpenAL fixes (loop-state reset, effect filtering, audio worker thread) |
| Mods (SMAPI) | No | Bundled SMAPI, enabled automatically when `Mods/` has mods |
| Install | Follow forum steps | `setup.sh` + Deskbar entry |
| Source | Not published | This repository (MIT) |

### vs. the PortMaster port it's based on ([Producdevity/portmaster-stardew-valley-mainline](https://github.com/Producdevity/portmaster-stardew-valley-mainline))

This repo is a fork of that project and keeps its full history; the PortMaster
build still works (see [`docs/PortMaster.md`](docs/PortMaster.md) and [`docs/PortMaster-CONTRIBUTING.md`](docs/PortMaster-CONTRIBUTING.md)). The Haiku
differences:

- **Target:** Haiku x86_64 desktop instead of aarch64 Linux handhelds.
- **Runtime:** .NET 9+ for Haiku with roll-forward, instead of a bundled
  Microsoft .NET 6 runtime (none exists for Haiku).
- **Desktop profile:** the patcher's `--profile desktop` keeps vanilla window
  modes, UI scale, zoom and mouse input, skipping the handheld rewrites (forced
  borderless fixed resolution, display-size scaling, synthesised pointer).
  MonoGame mouse motion is re-enabled on Haiku.
- **More robust patcher:** new `--runtime-target`, `--framework-version`,
  `--roll-forward` and `--patch-steamkit` options; it accepts any 6.0.x
  runtime pack in the game files, not just 6.0.32. PortMaster defaults are
  unchanged.
- **No GL4ES or PortMaster tooling:** native OpenGL through Mesa, no gptokeyb.
- **Setup and game download on the device** instead of copying from a PC.
- **Build fix:** `bootstrap-monogame-thirdparty.sh` fetches the pinned NVorbis
  commit directly (a shallow clone couldn't check it out).

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

## Troubleshooting

| Symptom | Fix |
|---|---|
| "This copy is in the Trash" | Your Terminal is still in an old folder. Open a new Terminal, `cd` to the new folder. |
| Download stops progressing | The watchdog restarts it after 3 minutes. If it keeps stalling: `SDV_MAX_DOWNLOADS=2 ./get-game-steam.sh` |
| Steam Guard asked every time | Answer **Y** to "Remember this Steam login" once. |
| `PlatformNotSupportedException ... GetAllNetworkInterfaces` | You're running an old package; update it. |
| Game doesn't start | Check `log.txt`. Re-patch with `SDV_FORCE_PATCH=1 ./StardewValley.sh`. Confirm `gamedata/` has `Stardew Valley.dll`. |
| Mods misbehave | `SDV_VANILLA=1 ./StardewValley.sh` to rule out the base game, then see [Mods](#mods-smapi). |

Saves live in `~/.config/StardewValley/Saves`.
[Open an issue](https://github.com/Techniix/Stardew-Valley_HaikuOS/issues/new/choose)
with your `VERSION`, Haiku revision and `log.txt`.

## Building from source

The managed parts are platform-neutral and build on Linux (or on Haiku with the
.NET SDK). Requires the .NET 8 SDK, git, curl, zip/unzip.

```sh
git clone https://github.com/Techniix/Stardew-Valley_HaikuOS
cd Stardew-Valley_HaikuOS
./haiku/build-managed.sh        # -> haiku/out/StardewValley-haiku.zip
```

The script clones the MonoGame fork at a pinned commit into `../MonoGame` if
it's missing, applies [`patches/monogame/`](patches/monogame/), fetches SMAPI
(checksum-verified) and assembles the package. The native shims are built on
Haiku by `setup.sh`.

CI ([`.github/workflows/haiku-package.yml`](.github/workflows/haiku-package.yml))
builds the package on every push; pushing a `haiku-v*` tag publishes a release.
See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Roadmap

- [x] Game launches on real Haiku hardware
- [x] Setup script, Steam download, Deskbar entry
- [ ] Confirm SMAPI/Harmony on Haiku
- [ ] Gamepad testing
- [ ] `.hpkg` package and HaikuDepot submission
- [ ] GOG downloader alongside Steam
- [ ] Upstream fixes: SteamKit2 (`PlatformNotSupportedException` fallback),
      MonoGame Haiku support, .NET `NetworkInterface` on Haiku

## Credits & license

- Original PortMaster port, MonoGame fork, patcher and shims:
  [Producdevity](https://github.com/Producdevity)
- .NET for Haiku: [trungnt2910](https://github.com/trungnt2910)
- SMAPI: [Pathoschild](https://github.com/Pathoschild/SMAPI);
  DepotDownloader/SteamKit2: [SteamRE](https://github.com/SteamRE)
- Haiku port: Dalton Singleton ([@Techniix](https://github.com/Techniix))

MIT, see [`LICENSE`](LICENSE). Third-party components and the game-files policy
are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Stardew Valley is © ConcernedApe LLC. This project is unofficial and not
affiliated with ConcernedApe.
