# odin-sdl2-x

Game-dev experiments using [Odin](https://odin-lang.org/) and [SDL2](https://www.libsdl.org/)

## Prerequisites

- [Odin](https://odin-lang.org/)

## Project setup

For Windows, run the setup script to copy the required .dll files from the Odin
vendor library into this project directory.

```sh
odin build setup/setup.odin -file
./setup
```

For linux (tested on Debian), you will need to install the dependencies:
```sh
sudo apt-get install libsdl2-dev
sudo apt-get install libsdl2-ttf-dev
```

## Running the launcher

This allows launching some of the other examples after setting which monitor
they should open on, and what resolution and refresh rate to use.

```sh
odin run .
```

## Running standalone examples

```sh
odin run breakout/breakout.odin -file -o:speed
odin run dynamic_text/dynamic_text.odin -file
odin run shader/shader.odin -file
odin run ui/ui.odin -file
```
