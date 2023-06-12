# Linux Notes

Documents getting examples running on linux and troubleshooting.

Currently only tested on Debian running on a chromebook - may not
apply to other distros

## Project setup

You will need to install/build all the dependencies instead of
copying the DLL files from the vendor libraries like on Windows.
```sh
sudo apt-get install libsdl2-dev
sudo apt-get install libsdl2-ttf-dev
```

### miniaudio

clone repo

create new file:
```c
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
```

Build as static library, then copy it into `Odin/vendor/miniaudio/lib/` folder

```sh
gcc -c miniaudio.c
ar rcs miniaudio.a miniaudio.o
cp *.a ../Odin/vendor/miniaudio/lib/
````

Build game with extra linker flags

```shell
odin build breakout/breakout.odin -file -extra-linker-flags:"-ldl -lpthread"
```

Unfortunatly, the game crashes with error:
```shell
malloc(): invalid size (unsorted)
Aborted (core dumped)
```

For now disabled miniaudio when not on Windows

### STB

Build as static libraries, then copy them into `Odin/vendor/stb/lib/` folder

```sh
gcc -c stb_truetype.c
gcc -c stb_image.c
ar rcs stb_truetype.a stb_truetype.o
ar rcs stb_image.a stb_image.o
cp *.a ../Odin/vendor/stb/lib/
```

## Things that did not work

Installing `libsdl2-2.0-0` does not work for some reason, use
`libsdl2-dev` instead.

Using `libminiaudio.so` or `libminiaudio.so.1` as shared object name

Using shared object was able to compile, but failed when trying to run the game

```shell
gcc -c -fPIC -o miniaudio.o miniaudio.c
gcc -shared -fPIC -Wl,-soname,libminiaudio.so -o libminiaudio.so.0.11.17 miniaudio.o -lc
```

create link in project directory (only `miniaudio.so` worked as name)

```shell
ln -s ../libminiaudio.so.0.11.17 miniaudio.so
```

Build game with extra linker flags
```shell
odin build breakout/breakout.odin -file -extra-linker-flags:"-L. -ldl -lpthread -lminiaudio"
```

Fails when trying to run the game:
```shell
error while loading shared libraries: libminiaudio.so: cannot open shared object file: No such file or directory
```

## Misc things

You can see where all the files got installed to using dpkg.
Not sure if this is useful, but thought it was interesting.
```sh
dpkg -L libsdl2-2.0-0
```

Get list of search paths for linker:
```sh
ld --verbose | grep SEARCH_DIR | tr -s ' ;' \012
```

List symbols in shared object file:
```sh
readelf -Ws --dyn-syms stb_truetype.so
```