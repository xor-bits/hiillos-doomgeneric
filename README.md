# doomgeneric
The purpose of doomgeneric is to make porting Doom easier.
Of course Doom is already portable but with doomgeneric it is possible with just a few functions.

To try it you will need a WAD file (game data). If you don't own the game, shareware version is freely available (doom1.wad).

## usage with hiillos

```bash
# compile and install doom for hiillos
# (assuming that hiillos is cloned at ../hiillos)
zig build --prominent-compile-errors --summary none \
    -Doptimize=ReleaseSafe

cp zig-out/bin/doom ../hiillos/asset/sbin/
```

<img width="1280" height="827" alt="image" src="https://github.com/user-attachments/assets/aa348332-9320-43f6-8714-6bfe59985ee7" />
