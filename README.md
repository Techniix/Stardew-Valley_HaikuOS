# Stardew Valley for HaikuOS

Run Stardew Valley 1.6 natively on [Haiku](https://www.haiku-os.org/) x86_64,
with mod support, using the Haiku port of .NET. One script sets everything up
and can download your own copy of the game straight from Steam on Haiku.

**This project contains no game files.** You need to own Stardew Valley
(Steam, or the Windows build from GOG).

> **Status: playable.** Setup, Steam download, updates, sound, gamepads and
> launching from Terminal or the Deskbar are confirmed on real hardware
> (Haiku hrev60368, Ryzen 5 7600X, RTX 5070), where the game holds a steady
> 60 fps. Not confirmed yet: SMAPI/mods and direct-IP multiplayer. Online
> play via Steam friends or invite codes isn't possible on Haiku (see
> [Multiplayer](#multiplayer)). Bug reports with `log.txt` are very welcome.

- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [How this differs from other ports](#how-this-differs-from-other-ports)
- [Gamepads](#gamepads)
- [Multiplayer](#multiplayer)
- [Mods (SMAPI)](#mods-smapi)
- [Performance and profiling](#performance-and-profiling)
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
| Gamepad | If a controller is connected but not set up, offers to map it (optional) |
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
- **Haiku media kit race:** sometimes the game segfaults in
  `BTimeSource::GetTime` as audio starts. It's a race in Haiku's media kit,
  not in the game: a node's time source object can be freed while its
  playback thread still uses it (details and upstream report:
  [`docs/upstream/haiku-media-timesource-race.md`](docs/upstream/haiku-media-timesource-race.md)).
  It's timing-dependent, so the launcher changes nothing up front. It also
  fires while the process tears down after some *other* failure (in every
  case so far where we had the game's log, that's when it happened), so a
  debug report showing it isn't proof that audio was the cause: the launcher
  first checks the log for an error from the game itself and reports that
  instead.
  For a plain crash, it offers to **restart the media services and retry**
  (a small helper, `libs/sdv-media-helper`, does what Preferences → Media
  does) or to **play without sound**.
- **Working directory:** SDL2 on Haiku changes the working directory to the
  executable's folder (`dotnet/`) when started from Deskbar/Tracker (no
  `TERM` set). The game loads some content via relative paths, so that broke
  Deskbar launches. The launcher sets `TERM` so SDL leaves it alone.
- **Multiplayer networking:** Haiku's .NET doesn't implement
  `System.Net.NetworkInformation`, which the game's networking library
  (Lidgren) calls when it starts a connection, so joining by IP crashed. The
  patcher replaces those lookups (used for LAN broadcast and peer IDs) with
  safe fallbacks (`--no-network-interfaces`).
- **Tool-swing freezes:** `Guid.NewGuid()` reads the OS's cryptographic
  random source, and on Haiku's .NET that takes tens of milliseconds per
  call. The game creates GUIDs on its main thread (for example for every weed
  you cut), which froze it for up to half a second. The patcher points the
  game's own calls at a fast version-4 GUID generator seeded once from the OS
  (`--fast-guid`); the IDs only need to be unique, not secret.
- **Window queries:** the game asks for its window's position and display
  every frame. On Haiku each of those SDL calls is a round trip to the
  `app_server`, which cost several percent of every frame, so the patched
  MonoGame caches them (moves, resizes and mode changes refresh the cache).
- **Exception log:** `logs/exceptions.txt` records every .NET exception as
  it's thrown (via `StardewPatches.dll`, loaded before the game), so errors
  the game wraps (e.g. "Could not load … asset!") keep their real cause.
  `SDV_EXCEPTION_LOG=0` turns it off.
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
├── gamepad.sh            set up a controller (writes gamecontrollerdb.txt)
├── tools/udp-relay.py    optional multiplayer relay for another machine
├── tools/TraceReport/    summarises SDV_TRACE traces (see Performance)
├── build-native.sh       builds libs/ (called by setup.sh)
├── gamedata/             patched game files (yours)
├── steam-depot/          untouched Steam download (yours)
├── Mods/                 SMAPI mods
├── dotnet/               .NET for Haiku (if installed by setup.sh)
├── libs/                 native shims
├── overrides/ dlls/ tools/   Haiku MonoGame build, patcher, SMAPI bundle
├── licenses/             third-party licenses
├── log.txt               output of the last game run
├── logs/                 exceptions.txt (every .NET exception from the last run),
│                         plus SDV_PROFILE / SDV_TRACE output
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
- **Haiku runtime fixes:** `--no-network-interfaces` (multiplayer networking)
  and `--fast-guid` (tool-swing freezes), plus MonoGame patches for Haiku
  detection, controllers present at startup, cached window queries, and a
  clean startup (the window appears once, in its final size and mode, with a
  "please wait" notification until then; `SDV_NO_LAUNCH_NOTICE=1` hides it).
- **Tools:** gamepad mapping (`gamepad.sh`), an exception log, and on-device
  profiling (`SDV_PROFILE`, `SDV_TRACE`).
- **No GL4ES or PortMaster tooling:** native OpenGL through Mesa, no gptokeyb.
- **Setup and game download on the device** instead of copying from a PC.
- **Build fix:** `bootstrap-monogame-thirdparty.sh` fetches the pinned NVorbis
  commit directly (a shallow clone couldn't check it out).

## Gamepads

SDL's Haiku joystick backend identifies a controller only by a GUID made
from its name, so no controller on Haiku matches SDL's built-in controller
database, and the game (which uses SDL's gamepad API) ignores it until it
has a mapping. `gamepad.sh` records one:

```sh
./gamepad.sh          # list controllers, then map one
./gamepad.sh list     # list controllers only
./gamepad.sh test     # show input exactly as the game will see it
./gamepad.sh raw      # show the raw values SDL reads (diagnostics)
```

It asks you to press each button and move each stick (wait 10 seconds to
skip anything your controller doesn't have) and saves the result to
`gamecontrollerdb.txt` in the package folder. The launcher loads it for the
game through `SDL_GAMECONTROLLERCONFIG_FILE`. Mappings are keyed on the
controller's name, so they keep working on any USB port.

Notes:

- Haiku's SDL backend doesn't detect controllers plugged in later. Connect
  the controller **before** starting the game.
- The controller has to work in Haiku first: it should appear in
  **Preferences → Joysticks**. If it doesn't, that's a driver issue, not
  something the mapping can fix.
- `setup.sh` builds the tool (`libs/sdv-gamepad`); it needs the
  `libsdl2_devel` package, which setup installs.
- A wrong mapping (e.g. a stick bound to a trigger axis that rests at its
  minimum) makes the cursor drift and fires random input as soon as the game
  starts. Delete `gamecontrollerdb.txt` and map again, or start with
  `SDV_NO_GAMEPAD=1 ./StardewValley.sh` to ignore controllers entirely.
- Stardew's controls follow the Xbox layout: map by button *position*
  (bottom face button = A), not by the letter printed on the controller.
- Some XInput controllers (for example 8BitDo pads in X-input mode) expect
  the host to send an initialisation command that Haiku's stock `usb_hid`
  driver doesn't send; they can blink and switch themselves off after a
  while. Reconnecting (or rebooting) brings them back. That's a driver
  limitation, not something the port can work around.

## Multiplayer

| Method | On Haiku |
|---|---|
| Steam friends list, Steam invitations, invite codes | **Not available.** These need a running Steam client (or GOG Galaxy) signed in on the same machine. Neither exists for Haiku, so the game hides these options. |
| Direct IP / LAN (including joining Steam- or GOG-hosted farms) | **Should work** (not yet confirmed). Needs no Steam or GOG client on Haiku. See below. |

Direct IP works across platforms: a Haiku player can join a host on
Windows, macOS or Linux, or host for players on those platforms:

- **Joining:** Co-op → Join → **Join LAN Game**, then enter the host's
  IP address (LAN address, or their public IP for internet play).
- **Hosting:** in the game's Options, under Multiplayer, make sure
  **Accept IP connections** is on. For internet play, forward **UDP port
  24642** on your router to your Haiku machine, then share your public IP
  with the other players. On the same network, share your LAN address.

### Joining a Steam- or GOG-hosted farm from Haiku

The host's farm can accept direct-IP players at the same time as Steam/GOG
players: the host only needs **Accept IP connections** enabled (Options →
Multiplayer). Join LAN Game accepts `address:port`, so any way of making the
host's UDP port reachable works:

| Option | Host side | Haiku side |
|---|---|---|
| Port forwarding | Forward UDP 24642 to the host PC | Join `host-public-ip:24642` |
| UDP tunnel service (e.g. [playit.gg](https://playit.gg), free tier supports UDP) | Run the tunnel agent with a UDP tunnel to local port 24642 | Join the tunnel's `address:port` |
| VPN mesh | Join a WireGuard/Tailscale network | Join the same network with [Sotoportego](https://github.com/atomozero/Sotoportego) (native Haiku VPN client; Tailscale support is experimental), then join the host's VPN address |
| Relay through another LAN machine | Reachable from that machine (e.g. over a VPN client Haiku can't run) | Run [`tools/udp-relay.py`](tools/udp-relay.py) on the LAN machine, then join *its* LAN address |

The relay is a small Python 3 script (standard library only) for when the
host is reachable from some machine on your network but not from Haiku:

```sh
python3 tools/udp-relay.py --target HOST_ADDRESS:24642
```

It listens on UDP 24642 on that machine and forwards each player's traffic
to the host. Note that a player already *in* the farm can't relay for
others from inside the game: every player connects to the host directly.

All players need the same game version (and the same content mods), and the
farm needs a free cabin.

Steam/GOG invite codes and friends-list joining could only come back with a
working Steam or Galaxy client on Haiku, which this project doesn't attempt.

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

## Performance and profiling

On the test machine the game runs at a steady 60 fps. The remaining short
hitches come from first-time work: shaders compiling in the graphics driver,
textures uploading when you enter a new area, and the game's own work at
the start of a day.

Two switches help find the cause when something stutters:

```sh
SDV_PROFILE=1 ./StardewValley.sh   # frame times and asset loads -> logs/*.csv
SDV_TRACE=1 ./StardewValley.sh     # also a CPU trace -> logs/trace-report.txt
```

- `SDV_PROFILE=1` writes `logs/perf-latest.csv` (per-second stats),
  `logs/slow-frame-latest.csv` (every frame over 25 ms, split into game
  logic, drawing and presenting, with garbage-collection counts) and
  `logs/content-load-latest.csv` (how long each asset took to load).
- `SDV_TRACE=1` also records a .NET CPU-sampling trace (EventPipe). After
  you quit, `tools/TraceReport` turns it into `logs/trace-report.txt`: the
  call stacks the game's main thread was in during the slow frames,
  including calls that were blocked waiting. Startup is slower while
  tracing and the trace grows by a few MB per second, so keep traced
  sessions to a few minutes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "This copy is in the Trash" | Your Terminal is still in an old folder. Open a new Terminal, `cd` to the new folder. |
| Download stops progressing | The watchdog restarts it after 3 minutes. If it keeps stalling: `SDV_MAX_DOWNLOADS=2 ./get-game-steam.sh` |
| Steam Guard asked every time | Answer **Y** to "Remember this Steam login" once. |
| `PlatformNotSupportedException ... GetAllNetworkInterfaces` | You're running an old package; update it. |
| "Stardew Valley stopped with an error" | The game itself failed. Attach `log.txt` and `logs/exceptions.txt` to an issue. |
| Crash in `BTimeSource::GetTime` (debug report) | First check `log.txt` for an `Unhandled exception`; if there is one, that's the real problem and the media crash is a side effect. Otherwise it's the Haiku media kit race. Click **Terminate** in the debugger, then **Restart media & retry** in the launcher's prompt. If it keeps happening: `SDV_RESTART_MEDIA=1 ./StardewValley.sh` restarts them before every launch; `SDV_NO_AUDIO=1` plays without sound. |
| Game doesn't start | Check `log.txt`. Re-patch with `SDV_FORCE_PATCH=1 ./StardewValley.sh`. Confirm `gamedata/` has `Stardew Valley.dll`. |
| Controller does nothing in game | Run `./gamepad.sh`. If it says "NOT mapped", map it. If it lists no controller, check **Preferences → Joysticks**. Connect it before starting the game. |
| Stutter or freezes | Play a few minutes with `SDV_TRACE=1 ./StardewValley.sh` where it happens, and attach `logs/trace-report.txt` and `logs/slow-frame-latest.csv` to an issue. See [Performance and profiling](#performance-and-profiling). |
| Brief black screens in fullscreen | Try **Windowed Borderless** in the game's display options. It looks the same as fullscreen and may avoid them. |
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
builds the package on every push and publishes releases (see [`CONTRIBUTING.md`](CONTRIBUTING.md#releases)).
See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Roadmap

- [x] Game launches on real Haiku hardware
- [x] Setup script, Steam download, Deskbar entry
- [x] Sound
- [x] Gamepads (with a mapping from `gamepad.sh`)
- [x] Smooth frame pacing (60 fps on the test machine)
- [ ] Get the media kit time-source race fixed in Haiku
- [ ] Confirm SMAPI/Harmony on Haiku
- [ ] Confirm direct-IP multiplayer (host and join)
- [ ] `.hpkg` package and HaikuDepot submission
- [ ] GOG downloader alongside Steam
- [ ] Upstream fixes: SteamKit2 (`PlatformNotSupportedException` fallback),
      MonoGame Haiku support, .NET on Haiku (`NetworkInterface`, slow
      `Guid.NewGuid()`)

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
