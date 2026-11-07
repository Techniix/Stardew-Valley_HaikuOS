# Haiku patches for MonoGame

Apply these to the `portmaster-stardew-mainline` branch of
[Producdevity/MonoGame](https://github.com/Producdevity/MonoGame)
(`haiku/build-managed.sh` does this automatically):

1. `0001` Detect Haiku as its own OS (previously treated as macOS), load
   `dlopen`/`dlsym` from `libroot.so`, use ELF sonames for SDL2/OpenAL, and add a
   `haiku-x64` RID.
2. `0002` Re-enable SDL mouse motion on Haiku (disabled upstream for handhelds).
3. `0003` Detect Haiku from `RuntimeInformation.OSDescription`. The original
   `uname` call imports `libc`, which Haiku doesn't have (its C library is
   `libroot.so`), so detection in `0001` alone would silently fail.
4. `0004` Close the OpenAL device on process exit on Haiku. Otherwise Haiku's
   media library is torn down while OpenAL's playback thread still runs, and
   the game segfaults in `BTimeSource::GetTime` when quitting.

These patches modify MonoGame source files and are licensed under the
**Microsoft Public License (Ms-PL)**, like MonoGame itself.
