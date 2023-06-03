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

## Things that did not work

Installing `libsdl2-2.0-0` does not work for some reason, use
`libsdl2-dev` instead.

## Misc things

You can see where all the files got installed to using dpkg.
Not sure if this is useful, but thought it was interesting.
```sh
dpkg -L libsdl2-2.0-0
```
