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
  (8.0 or newer). Haiku has no .NET 6, so the game runs on the newest
  installed runtime via `rollForward: LatestMajor`.
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
| Mods (SMAPI) | No | Planned, via the PortMaster SMAPI bundling |
| Source | Not published | This repository, MIT |
| Install | Follow forum steps | `StardewValley.sh` launcher; `.hpkg` planned |

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
- **Build fix:** `bootstrap-monogame-thirdparty.sh` now fetches the pinned
  NVorbis commit directly (a shallow clone couldn't check it out).

## Install (Haiku)

See [`haiku/INSTALL.txt`](haiku/INSTALL.txt). Short version:

```sh
pkgman install libsdl2 openal gcc haiku_devel
# install .NET 8+ from github.com/trungnt2910/dotnet-builds
./build-native.sh
# copy your Stardew Valley folder (with "Stardew Valley.dll") into gamedata/
./StardewValley.sh
```

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
- [ ] SMAPI mod support
- [ ] `.hpkg` with icon and Deskbar entry, HaikuDepot submission
- [ ] Optional bundled .NET runtime
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
