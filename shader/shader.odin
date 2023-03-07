package main

import "core:fmt"
import "core:time"
import "core:strings"

import "vendor:sdl2"


SCREEN_WIDTH : i32 = 1280
SCREEN_HEIGHT : i32 = 960
TARGET_DT : f64 = 1000 / 60
perf_frequency : f64

Game :: struct {
    fps: f64,
}
game := Game{}

main :: proc() {

    assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
    defer sdl2.Quit()

    window := sdl2.CreateWindow(
        "UI Example",
        sdl2.WINDOWPOS_UNDEFINED,
        sdl2.WINDOWPOS_UNDEFINED,
        SCREEN_WIDTH,
        SCREEN_HEIGHT,
        {.SHOWN, .RESIZABLE},
    )
    assert(window != nil, sdl2.GetErrorString())
    defer sdl2.DestroyWindow(window)

    // Init Renderer with OpenGL
    backend_index: i32 = -1
    driver_count := sdl2.GetNumRenderDrivers()
    if driver_count <= 0 {
        fmt.eprintln("No render drivers available")
        return
    }
    for i in 0..<driver_count {
        info: sdl2.RendererInfo
        if err := sdl2.GetRenderDriverInfo(i, &info); err == 0 {
            // fmt.println("found driver:", info.name)
            if info.name == "opengl" {
                backend_index = i
            }
        }
    }

    renderer := sdl2.CreateRenderer(window, backend_index, {.ACCELERATED, .PRESENTVSYNC})
    assert(renderer != nil, sdl2.GetErrorString())
    defer sdl2.DestroyRenderer(renderer)

    perf_frequency = f64(sdl2.GetPerformanceFrequency())
    start : f64
    end : f64

    game_loop : for {
        start = get_time()
        // Update
        // Handle input events
        event : sdl2.Event
        for sdl2.PollEvent(&event) {
            #partial switch event.type {
                case .QUIT:
                    break game_loop
                case .KEYDOWN, .KEYUP:
                    if event.type == .KEYUP && event.key.keysym.sym == .ESCAPE {
                        sdl2.PushEvent(&sdl2.Event{type = .QUIT})
                    }
            }
        }

        // Render
        // Draw UI stuff here
        render(renderer, {128, 128, 128, 255})

        free_all(context.temp_allocator)

        // Timing (avoid looping too fast)
        end = get_time()
        to_sleep := time.Duration((TARGET_DT - (end - start)) * f64(time.Millisecond))
        time.accurate_sleep(to_sleep)
        end = get_time()
        game.fps = 1000 / (end - start)
    }
}


get_time :: proc() -> f64 {
    return f64(sdl2.GetPerformanceCounter()) * 1000 / perf_frequency
}


render :: proc(renderer: ^sdl2.Renderer, bg: [4]u8) {
    viewport_rect := sdl2.Rect{}
    sdl2.GetRendererOutputSize(renderer, &viewport_rect.w, &viewport_rect.h)
    sdl2.RenderSetViewport(renderer, &viewport_rect)
    sdl2.RenderSetClipRect(renderer, &viewport_rect)
    sdl2.SetRenderDrawColor(renderer, bg.r, bg.g, bg.b, bg.a)
    sdl2.RenderClear(renderer)

    sdl2.RenderPresent(renderer)
}
