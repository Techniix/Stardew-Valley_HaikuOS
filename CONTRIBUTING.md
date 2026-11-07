# Contributing

Bug reports and fixes are welcome. Please use the issue templates and include
your package `VERSION`, Haiku revision and `log.txt`.

**Never commit or attach Stardew Valley game files**, and never paste anything
containing your Steam password.

## Repository layout

| Path | What it is |
|---|---|
| `haiku/` | Haiku launcher, setup, Steam downloader and build scripts |
| `patches/monogame/` | Haiku patches for the MonoGame fork (Ms-PL) |
| `build/src/MainlineGameDataPatcher/` | Patcher shared with the PortMaster build (Mono.Cecil) |
| `build/src/native/` | Native shims (C) |
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

Push a tag named `haiku-vX.Y.Z`; CI builds the package and publishes a GitHub
release with `StardewValley-haiku.zip`.

## Upstream work

Where possible, fix things upstream too: MonoGame Haiku support, the SteamKit2
machine-ID fallback (`PlatformNotSupportedException`), and `NetworkInterface`
in .NET for Haiku.
