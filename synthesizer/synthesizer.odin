package synthesizer

import "core:fmt"
import "core:mem"
import "core:sync"
import "core:time"
import "vendor:sdl2"
import ma "vendor:miniaudio"

import "pitch"


main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	_main()

	for _, leak in track.allocation_map {
		fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
	}
	for bad_free in track.bad_free_array {
		fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
	}
}

_main :: proc() {
	window_width: i32 = 1200
	window_height: i32 = 800

	window := sdl2.CreateWindow(
		"Circumcircle Test",
		sdl2.WINDOWPOS_UNDEFINED,
		sdl2.WINDOWPOS_UNDEFINED,
		window_width,
		window_height,
		{.SHOWN},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	renderer := sdl2.CreateRenderer(window, -1, sdl2.RENDERER_ACCELERATED)
	assert(renderer != nil, sdl2.GetErrorString())
	defer sdl2.DestroyRenderer(renderer)

	run(window_width, window_height, renderer, 60)
}

// for device.pUserData not sure if this is needed...
// mutex := sync.Mutex{}


data_callback :: proc "cdecl" (device: ^ma.device, output, input: rawptr, frame_count: u32) {
	sine: ^ma.waveform
	// sync.mutex_lock(&mutex)
	sine = cast(^ma.waveform)device.pUserData
	// sync.mutex_unlock(&mutex)
	ma.waveform_read_pcm_frames(sine, output, cast(u64)frame_count, nil)
}

configure_wave :: proc(wave: ^ma.waveform, device: ^ma.device, config: ^ma.device_config) {
	cfg: ma.waveform_config
	cfg = ma.waveform_config_init(
		config.playback.format,
		device.playback.channels,
		device.sampleRate,
		ma.waveform_type.sine,
		0.5,
		pitch.c,
	)
	ma.waveform_init(&cfg, wave)
}
start_device :: proc(device: ^ma.device) -> bool {
	if ma.device_is_started(device) {
		return false
	}
	result := ma.device_start(device)
	if result != ma.result.SUCCESS {
		fmt.eprintf("Error starting device: %d\n", result)
		return false
	}
	return true
}
stop_device :: proc(device: ^ma.device) {
	ma.device_stop(device)
}

run :: proc(window_width: i32, window_height: i32, renderer: ^sdl2.Renderer, refresh_rate: i32) {
	config := ma.device_config_init(ma.device_type.playback)
	config.playback.format = ma.format.f32
	config.playback.channels = 2
	config.sampleRate = 48000
	config.dataCallback = data_callback

	wave: ma.waveform
	config.pUserData = &wave

	device: ma.device
	result := ma.device_init(nil, &config, &device)
	if result != ma.result.SUCCESS {
		fmt.eprintf("Error initializing device: %d\n", result)
		return
	}
	defer ma.device_uninit(&device)

	configure_wave(&wave, &device, &config)

	pitch_idx := 0
	loop_i := 0
	space_down := false

	target_dt: f64 = 1000 / f64(refresh_rate)
	start: f64
	end: f64

	game_loop: for {
		start = get_time()
		// change note at 4 beats a second
		loop_i += 1
		if loop_i > 15 {
			loop_i = 0
			pitch_idx = pitch.next_pitch(pitch_idx, pitch.SCALE[:])
			ma.waveform_set_frequency(&wave, pitch.SCALE[pitch_idx])
		}
		// Handle input events
		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break game_loop
			case .WINDOWEVENT:
				if event.window.event == .CLOSE {
					sdl2.PushEvent(&sdl2.Event{type = .QUIT})
				}
			case .KEYDOWN:
				#partial switch event.key.keysym.scancode {
				case .SPACE:
					if !space_down {
						pitch_idx = 0
						start_device(&device)
						loop_i = 0
						ma.waveform_set_frequency(&wave, pitch.SCALE[pitch_idx])
					}
					space_down = true
				}

			case .KEYUP:
				#partial switch event.key.keysym.scancode {
				case .ESCAPE:
					sdl2.PushEvent(&sdl2.Event{type = .QUIT})
				case .SPACE:
					space_down = false
					stop_device(&device)
				}
			}
		}

		// Render
		sdl2.RenderPresent(renderer)
		sdl2.SetRenderDrawColor(renderer, 0, 0, 0, 255)
		sdl2.RenderClear(renderer)

		free_all(context.temp_allocator)

		// Timing (avoid looping too fast)
		end = get_time()
		to_sleep := time.Duration((target_dt - (end - start)) * f64(time.Millisecond))
		time.accurate_sleep(to_sleep)
		end = get_time()
		// game.fps = 1000 / (end - start)
	}
}


get_time :: proc "contextless" () -> f64 {
	return f64(sdl2.GetPerformanceCounter()) * 1000 / f64(sdl2.GetPerformanceFrequency())
}
