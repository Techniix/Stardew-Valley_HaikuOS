# Contributing

Bug reports and fixes are welcome. Please use the issue templates and include
your package `VERSION`, Haiku revision and `log.txt`.

**Never commit or attach Stardew Valley game files**, and never paste anything
containing your Steam password.

## Repository layout

| Path | What it is |
|---|---|
| `haiku/` | Haiku launcher, setup, Steam downloader and build scripts |
| `haiku/haikuports/` | HaikuPorter recipe for the `.hpkg` (see `docs/Packaging.md`) |
| `haiku/publish-hpkg.sh` | Builds the `.hpkg` on Haiku and publishes it |
| `patches/monogame/` | Haiku patches for the MonoGame fork (Ms-PL) |
| `build/src/MainlineGameDataPatcher/` | Patcher shared with the PortMaster build (Mono.Cecil) |
| `build/src/native/` | Native shims and Haiku tools (C/C++) |
| `build/src/StardewPatches.Mainline/` | Loaded before the game (`MONOGAME_PATCH`); writes the exception log |
| `build/src/TraceReport/` | Summarises `SDV_TRACE` EventPipe traces (TraceEvent) |
| `tools/udp-relay.py` | Optional multiplayer UDP relay |
| `portmaster_stardewvalley_mainline/`, `build/scripts/`, `scripts/` | Upstream PortMaster package; keep it working |

## Building and testing

```sh
./haiku/build-managed.sh                    # build the package on Linux
shellcheck -S warning haiku/*.sh            # CI runs this too
```

Test on Haiku with a real copy of the game: `./setup.sh`, then
`./StardewValley.sh`, and if you touched mod handling, at least one SMAPI mod.

## Changing MonoGame

Work in `../MonoGame` on top of the pinned commit in
`haiku/build-managed.sh`, commit there, then regenerate the patches:

```sh
git -C ../MonoGame format-patch -N <pinned-commit> -o "$PWD/patches/monogame/"
```

## Patcher changes

`MainlineGameDataPatcher` is also used by the PortMaster build. New behaviour
must be opt-in via arguments so the PortMaster defaults stay unchanged.

## Releases

Add release notes as `docs/release-notes/haiku-vX.Y.Z.md`, then either push a
tag named `haiku-vX.Y.Z`, or open **Actions → Haiku package → Run workflow**
and enter `haiku-vX.Y.Z` as the release tag. CI builds the package (its
`VERSION` file is the tag), creates the tag and publishes a GitHub release
with `StardewValley-haiku.zip`.

Then, on Haiku, run `./haiku/publish-hpkg.sh` to build the Haiku package from
that release, attach it to the release and publish it in the package
repository (details in `docs/Packaging.md`).

## Upstream work

Where possible, fix things upstream too: MonoGame Haiku support, the SteamKit2
machine-ID fallback (`PlatformNotSupportedException`), and `NetworkInterface`
and the slow `Guid.NewGuid()` in .NET for Haiku.
