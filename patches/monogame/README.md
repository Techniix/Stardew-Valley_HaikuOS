# Haiku patches for MonoGame

Apply these to the `portmaster-stardew-mainline` branch of
[Producdevity/MonoGame](https://github.com/Producdevity/MonoGame)
(`haiku/build-managed.sh` does this automatically):

1. `0001` Detect Haiku as its own OS (previously treated as macOS), load
   `dlopen`/`dlsym` from `libroot.so`, use ELF sonames for SDL2/OpenAL, and add a
   `haiku-x64` RID.
2. `0002` Re-enable SDL mouse motion on Haiku (disabled upstream for handhelds).

These patches modify MonoGame source files and are licensed under the
**Microsoft Public License (Ms-PL)**, like MonoGame itself.
