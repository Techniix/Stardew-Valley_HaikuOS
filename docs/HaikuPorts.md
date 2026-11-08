# Packaging for HaikuPorts / HaikuDepot

The recipe in [`haiku/haikuports/`](../haiku/haikuports/games-simulation/stardew_valley_haiku/)
builds a Haiku package (`.hpkg`) from a GitHub release. HaikuDepot lists what
HaikuPorts builds, so getting the recipe merged into
[haikuports/haikuports](https://github.com/haikuports/haikuports) is how the
game becomes installable from HaikuDepot.

## What the package does

- **Source:** the release zip (`StardewValley-haiku.zip`) for `haiku-v<version>`,
  plus the Haiku build of .NET from
  [trungnt2910/dotnet-builds](https://github.com/trungnt2910/dotnet-builds).
  HaikuPorter builds without network access, so the managed parts come prebuilt
  from the release, like `dev-lang/rust_bin` does for Rust.
- **Build:** compiles the native shims, gamepad tool and media helper from
  `native-src/`.
- **Install:** `/boot/system/apps/StardewValley`, with only the .NET runtime
  (about 40 MB, not the SDK) in `dotnet/` and a Deskbar entry. A `.packaged`
  marker makes the scripts keep game files, mods, logs and settings in
  `~/config/data/StardewValley` and skip the pkgman and build steps of setup.
- **No game files.** On first start without them, setup opens in Terminal and
  offers the Steam download, as in the zip release.

Licences: the port and .NET are MIT, SMAPI is LGPL-3.0 and MonoGame is Ms-PL
(shipped next to the recipe in `licenses/Ms-PL`; Haiku has no built-in copy).
All allow redistribution with their notices, which the package includes.

**Bundled .NET.** The licence allows it, but HaikuPorts generally prefers each
dependency as its own package. If reviewers ask, split .NET into a
`dev-lang/dotnet_bin` recipe (runtime from the same tarball, installed under
`$developDir` or `$libDir`), make this recipe require it, and drop the
`dotnet/` part of `INSTALL`. The launcher already finds `dotnet` on the `PATH`.

## Updating the recipe for a new release

1. Publish the release on GitHub (Actions → Haiku package → Run workflow).
2. Rename the recipe to the new version (`stardew_valley_haiku-<version>.recipe`);
   `portVersion` comes from the file name.
3. Update `CHECKSUM_SHA256`:
   `curl -sL <release zip URL> | sha256sum`.
4. Reset `REVISION` to `1` (increase it instead when only the recipe changes).
5. Build and test on Haiku (below).

## Building and testing on Haiku

```sh
# Once: haikuporter itself (see the HaikuPorts wiki Home page)
git clone --depth=50 https://github.com/haikuports/haikuporter.git ~/haikuporter
cp ~/haikuporter/haikuports-sample.conf ~/config/settings/haikuports.conf
#   edit it: PACKAGER="Name <email>", TREE_PATH="/boot/home/haikuports"
ln -s ~/haikuporter/haikuporter ~/config/non-packaged/bin/
git clone https://github.com/<you>/haikuports.git ~/haikuports   # your fork

# Each time
cp -r haiku/haikuports/games-simulation/stardew_valley_haiku ~/haikuports/games-simulation/
cd ~/haikuports
haikuporter --lint stardew_valley_haiku
haikuporter -S -j$(nproc) --no-source-packages --get-dependencies stardew_valley_haiku
pkgman install ~/haikuports/packages/stardew_valley_haiku-*.hpkg
```

Check that the game starts from the Deskbar on a clean account (no
`~/config/data/StardewValley`), that setup opens and downloads the game, and
that `pkgman uninstall stardew_valley_haiku` leaves your data folder alone.

## Submitting

HaikuPorts takes contributions as pull requests from feature branches; see its
[DevelopmentModel](https://github.com/haikuports/haikuports/wiki/DevelopmentModel)
page. In short:

1. Fork haikuports/haikuports on GitHub and clone your fork.
2. Add HaikuPorts as `upstream` and keep `master` in sync with
   `git pull upstream master`. Never commit to `master`.
3. `git checkout -b stardew_valley_haiku`, add the recipe folder, and commit
   with a message like `stardew_valley_haiku: new recipe`.
4. `git push origin stardew_valley_haiku` and open a pull request from your
   fork's page. Say in the description that the game data must be purchased,
   that nothing of the game is redistributed, and what you tested it on.
5. Answer review by amending (`git commit --amend`, `git push --force`); if the
   branch falls behind, `git rebase master` instead of merging. HaikuPorts
   wants one commit per recipe and no merge commits.

Before the first submission, also read the wiki's
[HaikuPorter-Guidelines](https://github.com/haikuports/haikuports/wiki/HaikuPorter-Guidelines)
(field order, summary and description rules) and
[HaikuPorter-BuildRecipes](https://github.com/haikuports/haikuports/wiki/HaikuPorter-BuildRecipes)
(recipe syntax).
