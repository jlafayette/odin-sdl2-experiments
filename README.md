# odin-sdl2-x

Game-dev experiments using [Odin](https://odin-lang.org/) and [SDL2](https://www.libsdl.org/)

## Prerequisites

- [Odin](https://odin-lang.org/)

## Project setup

This copies all the .dll files required from the Odin vendor library to this
project directory. This is required for Windows, not sure about other platforms
yet.

```sh
odin build setup/setup.odin -file
./setup
```

## Running the launcher

This allows launching some of the other examples after setting which monitor
they should open on, and what resolution and refresh rate to use.

```sh
odin run .
```

## Running standalone examples

```sh
odin run dynamic_text/dynamic_text.odin -file
odin run shader/shader.odin -file
odin run ui/ui.odin -file
```
