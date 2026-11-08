# Haiku package (.hpkg)

Besides the zip, each release is published as a Haiku package, built from the
HaikuPorter recipe in
[`haiku/haikuports/`](../haiku/haikuports/games-simulation/stardew_valley_haiku/).
It's attached to the GitHub release and published in the package repository
[Techniix/haiku-packages](https://github.com/Techniix/haiku-packages), so
HaikuDepot can install and update it.

The package is not part of HaikuPorts.

## Installing

```sh
pkgman add-repo https://techniix.github.io/haiku-packages/x86_64/current
pkgman install stardew_valley_haiku
```

Or download the `.hpkg` from a release and run `pkgman install <file>.hpkg`.

## What the package does

- **Source:** the release zip (`StardewValley-haiku.zip`), plus the Haiku build
  of .NET from [trungnt2910/dotnet-builds](https://github.com/trungnt2910/dotnet-builds).
  HaikuPorter builds without network access, so the managed parts come
  prebuilt from the release.
- **Build:** compiles the native shims, gamepad tool and media helper from
  `native-src/`.
- **Install:** `/boot/system/apps/StardewValley`, with only the .NET runtime
  (about 40 MB, not the SDK) in `dotnet/` and a Deskbar entry. A `.packaged`
  marker makes the scripts keep game files, mods, logs and settings in
  `~/config/settings/StardewValley` and skip the pkgman and build steps of
  setup. The game keeps its saves and options there too, so everything stays
  together and survives uninstalling the package.
- **No game files.** On first start without them, setup opens in Terminal and
  offers the Steam download, as in the zip release.

Licences: the port and .NET are MIT, SMAPI is LGPL-3.0 and MonoGame is Ms-PL
(shipped next to the recipe in `licenses/Ms-PL`; Haiku has no built-in copy).
All allow redistribution with their notices, which the package includes.

## Publishing a release as a package

After the release workflow has published the zip (see CONTRIBUTING.md), run
this on Haiku, from a clone of this repository:

```sh
./haiku/publish-hpkg.sh            # or: ./haiku/publish-hpkg.sh haiku-vX.Y.Z
```

It:

1. downloads the release zip and puts its version and checksum in the recipe;
2. builds the package with haikuporter (strict policy checks on);
3. adds it to the package repository with `update-repo.sh`, replacing the
   previous version, and pushes;
4. attaches the `.hpkg` to the GitHub release and adds install instructions to
   the release notes;
5. commits and pushes the recipe update.

To rebuild the same version after changing only the recipe, raise `REVISION`
in the recipe first.

### One-time setup

```sh
# haikuporter
pkgman install git
git clone --depth=50 https://github.com/haikuports/haikuporter.git ~/haikuporter
ln -s ~/haikuporter/haikuporter ~/config/non-packaged/bin/
cp ~/haikuporter/haikuports-sample.conf ~/config/settings/haikuports.conf
#   edit it: PACKAGER="Name <email>", TREE_PATH="/boot/home/haikuports"

# the HaikuPorts tree (haikuporter needs it for build dependencies)
git clone --depth=1 https://github.com/haikuports/haikuports.git ~/haikuports

# the package repository
git clone https://github.com/Techniix/haiku-packages.git ~/haiku-packages
```

GitHub access: a fine-grained personal access token with **Contents: Read and
write** on this repository and on `haiku-packages`. Either export it as
`GITHUB_TOKEN`, or let git's credential helper store it
(`git config --global credential.helper store`, then push once).

### Testing a package before publishing

Build without publishing, install it and check it on a clean account:

```sh
cp -r haiku/haikuports/games-simulation/stardew_valley_haiku ~/haikuports/games-simulation/
cd ~/haikuports
haikuporter -S -j$(nproc) --no-source-packages --get-dependencies stardew_valley_haiku
pkgman install packages/stardew_valley_haiku-*.hpkg
rm -rf games-simulation/stardew_valley_haiku
```

Check that it starts from the Deskbar without `~/config/settings/StardewValley`
(setup opens and downloads the game), that the game runs, and that
`pkgman uninstall stardew_valley_haiku` leaves that folder alone.
