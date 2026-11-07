# Third-party notices

This repository's own code (launcher, build scripts, patcher, native shims) is
under the MIT License in [`LICENSE`](LICENSE). It is derived from
[Producdevity/portmaster-stardew-valley-mainline](https://github.com/Producdevity/portmaster-stardew-valley-mainline)
(MIT, Copyright (c) 2026 Producdevity), whose full commit history is kept here.

Other components have their own licenses:

| Component | Where | License |
|---|---|---|
| MonoGame (Producdevity fork, `portmaster-stardew-mainline` branch) | built into `MonoGame.Framework.dll` | Ms-PL, see `portmaster_stardewvalley_mainline/stardewvalleymainline/licenses/LICENSE.MonoGame.txt` |
| Haiku patches to MonoGame | [`patches/monogame/`](patches/monogame/) | Ms-PL, same as the MonoGame files they modify |
| Mono.Cecil | used by `MainlineGameDataPatcher` | MIT, see `.../licenses/LICENSE.Mono.Cecil.txt` |
| NVorbis, StbImageSharp, StbImageWriteSharp | MonoGame third-party sources, fetched at build time | their own licenses (MIT) |
| Harmony, GL4ES | used only by the PortMaster package | see `.../licenses/` |

The Ms-PL requires that any distribution of MonoGame source code, or of the
patches above, keeps the Ms-PL notice. Binary distributions must use a license
that complies with the Ms-PL. That's why the Haiku package ships
`licenses/LICENSE.MonoGame.txt`.

## Game files

**This repository contains no Stardew Valley game files, assets or code, and
must never include them.** Stardew Valley is © ConcernedApe LLC. Players supply
their own legally obtained copy. This project is not affiliated with or
endorsed by ConcernedApe, Steam/Valve, GOG, or the MonoGame team.
