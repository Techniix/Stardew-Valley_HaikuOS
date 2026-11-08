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
4. `0004` Add controllers present at startup on Haiku. SDL2's Haiku joystick
   backend never sends `SDL_JOYDEVICEADDED` (no hotplug), which is MonoGame's
   only path to registering a gamepad.
5. `0005` Cache the window's display index for half a second (the game asks
   every frame, and on Haiku each query is an `app_server` round trip), and
   write the profiling CSVs from a background thread instead of opening and
   closing the file for every sample.
6. `0006` Cache the window position behind `ClientBounds`, which the game reads
   several times per frame; for a fullscreen window each read was an
   `app_server` round trip on Haiku. Moves, resizes and mode changes
   invalidate the cache.
7. `0007` On Haiku, keep the window hidden until the game has finished applying
   its saved window size and mode, so startup doesn't flash a white window
   through several sizes. `MONOGAME_SHOW_WINDOW_EARLY=1` turns this off.


These patches modify MonoGame source files and are licensed under the
**Microsoft Public License (Ms-PL)**, like MonoGame itself.
