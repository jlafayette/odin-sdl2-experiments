package synthesizer

import "core:fmt"
import "core:mem"
import "core:os"
import "core:runtime"
import "core:strings"
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
SAMPLE_FORMAT := ma.format.f32
CHANNEL_COUNT := 2
SAMPLE_SIZE := ma.get_bytes_per_sample(SAMPLE_FORMAT)
FRAME_SIZE := ma.get_bytes_per_frame(SAMPLE_FORMAT, u32(CHANNEL_COUNT))
SAMPLE_RATE := 48000
Decoder :: struct {
	decoder: ma.decoder,
	at_end:  bool,
}
Game :: struct {
	backing:  [dynamic]Decoder,
	decoders: []Decoder,
}
game_init :: proc(g: ^Game) {
	reserve_dynamic_array(&g.backing, 3)
	g.decoders = g.backing[:]
}
game_destroy :: proc(g: ^Game) {
	delete(g.backing)
}
game: Game

stop_event: ma.event

are_all_decoders_at_end :: proc "contextless" (game: ^Game) -> bool {
	for i := 0; i < len(game.decoders); i += 1 {
		if game.decoders[i].at_end == false {
			return false
		}
	}
	return true
}

// SAMPLE_FORMAT := ma.format.f32
// CHANNEL_COUNT := 2
// SAMPLE_RATE := 48000

read_and_mix_pcm_frames_f32 :: proc "cdecl" (
	decoder: ^ma.decoder,
	output: []f32,
	frame_count: u32,
) -> u32 {
	result: ma.result
	temp: [4096]f32
	temp_cap_in_frames: u64 = u64((size_of(temp) / size_of(temp[0])) / CHANNEL_COUNT)
	total_frames_read: u64 = 0

	for total_frames_read < u64(frame_count) {
		i_sample: u64
		frames_read_this_iteration: u64
		total_frames_remaining := u64(frame_count) - total_frames_read
		frames_to_read_this_iteration: u64 = temp_cap_in_frames
		if frames_to_read_this_iteration > total_frames_remaining {
			frames_to_read_this_iteration = total_frames_remaining
		}
		result = ma.decoder_read_pcm_frames(
			decoder,
			raw_data(temp[:]),
			frames_to_read_this_iteration,
			&frames_read_this_iteration,
		)
		if result != ma.result.SUCCESS || frames_read_this_iteration == 0 {
			break
		}
		max_i_sample := frames_to_read_this_iteration * u64(CHANNEL_COUNT)
		for i_sample = 0; i_sample < max_i_sample; i_sample += 1 {
			i_output := int(total_frames_read * u64(CHANNEL_COUNT) + i_sample)
			output[i_output] += temp[i_sample]
		}
		total_frames_read += frames_read_this_iteration
	}
	return u32(total_frames_read)
}


data_callback :: proc "cdecl" (device: ^ma.device, output, input: rawptr, frame_count: u32) {
	out_slice := transmute([]f32)runtime.Raw_Slice{output, 4096}

	for _, i in game.decoders {
		decoder := &game.decoders[i]
		if !decoder.at_end {
			frames_read := read_and_mix_pcm_frames_f32(&decoder.decoder, out_slice, frame_count)
			if frames_read < frame_count {
				decoder.at_end = true
			}
		}
	}

	if are_all_decoders_at_end(&game) {
		ma.event_signal(&stop_event)
	}
}

data_callback1 :: proc "cdecl" (device: ^ma.device, output, input: rawptr, frame_count: u32) {
	sine: ^ma.waveform
	// sync.mutex_lock(&mutex)
	sine = cast(^ma.waveform)device.pUserData
	// sync.mutex_unlock(&mutex)
	ma.waveform_read_pcm_frames(sine, output, cast(u64)frame_count, nil)
}
any_key_pressed :: proc() -> bool {
	state := sdl2.GetKeyboardStateAsSlice()
	// fmt.println(state)
	{
		using sdl2.Scancode
		if state[SPACE] == 1 do return true
		if state[Q] == 1 do return true
		if state[W] == 1 do return true
		if state[E] == 1 do return true
		if state[R] == 1 do return true
		if state[U] == 1 do return true
		if state[I] == 1 do return true
		if state[O] == 1 do return true
		if state[P] == 1 do return true
		if state[J] == 1 do return true
		if state[K] == 1 do return true
		if state[L] == 1 do return true
		if state[SEMICOLON] == 1 do return true
		if state[A] == 1 do return true
		if state[S] == 1 do return true
		if state[D] == 1 do return true
		if state[F] == 1 do return true
		if state[Z] == 1 do return true
		if state[X] == 1 do return true
		if state[C] == 1 do return true
		if state[V] == 1 do return true
		if state[M] == 1 do return true
		if state[COMMA] == 1 do return true
		if state[PERIOD] == 1 do return true
		if state[SLASH] == 1 do return true
	}
	return false
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
	if ma.device_is_started(device) {
		ma.device_stop(device)
	}
}

run :: proc(window_width: i32, window_height: i32, renderer: ^sdl2.Renderer, refresh_rate: i32) {
	game_init(&game)
	defer game_destroy(&game)

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

	// mixing multiple decoders
	decoder_config := ma.decoder_config_init(
		SAMPLE_FORMAT,
		cast(u32)CHANNEL_COUNT,
		cast(u32)SAMPLE_RATE,
	)

	// create decoder for each arg (sound file)
	args := os.args[1:]
	for path in args {
		d: Decoder
		cpath := strings.clone_to_cstring(path)
		defer delete(cpath)
		result := ma.decoder_init_file(cpath, &decoder_config, &d.decoder)
		if result != ma.result.SUCCESS {
			fmt.eprintf("Error: initializing decoder %s with %v\n", path, result)
			return
		}
		append(&game.backing, d)
	}
	game.decoders = game.backing[:]

	// Render
	sdl2.RenderPresent(renderer)
	sdl2.SetRenderDrawColor(renderer, 0, 0, 0, 255)
	sdl2.RenderClear(renderer)

	// if sound file decoders, wait for the stop event (all done)
	if len(game.decoders) > 0 {
		ok := start_device(&device)
		if !ok {
			fmt.eprintln("ERROR starting device")
			return
		}
		ma.event_init(&stop_event)

		ma.event_wait(&stop_event)

		return
	}

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
			// ma.waveform_set_frequency(&wave, pitch.SCALE[pitch_idx])
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
				case .Q:
					ma.waveform_set_frequency(&wave, pitch.c * 2)
				case .W:
					ma.waveform_set_frequency(&wave, pitch.d * 2)
				case .E:
					ma.waveform_set_frequency(&wave, pitch.e * 2)
				case .R:
					ma.waveform_set_frequency(&wave, pitch.f * 2)
				case .U:
					ma.waveform_set_frequency(&wave, pitch.g * 2)
				case .I:
					ma.waveform_set_frequency(&wave, pitch.a * 2)
				case .O:
					ma.waveform_set_frequency(&wave, pitch.b * 2)
				case .P:
					ma.waveform_set_frequency(&wave, pitch.c * 3)
				case .A:
					ma.waveform_set_frequency(&wave, pitch.c)
				case .S:
					ma.waveform_set_frequency(&wave, pitch.d)
				case .D:
					ma.waveform_set_frequency(&wave, pitch.e)
				case .F:
					ma.waveform_set_frequency(&wave, pitch.f)
				case .J:
					ma.waveform_set_frequency(&wave, pitch.g)
				case .K:
					ma.waveform_set_frequency(&wave, pitch.a)
				case .L:
					ma.waveform_set_frequency(&wave, pitch.b)
				case .SEMICOLON:
					ma.waveform_set_frequency(&wave, pitch.c * 2)
				case .Z:
					ma.waveform_set_frequency(&wave, pitch.c * 0.5)
				case .X:
					ma.waveform_set_frequency(&wave, pitch.d * 0.5)
				case .C:
					ma.waveform_set_frequency(&wave, pitch.e * 0.5)
				case .V:
					ma.waveform_set_frequency(&wave, pitch.f * 0.5)
				case .M:
					ma.waveform_set_frequency(&wave, pitch.g * 0.5)
				case .COMMA:
					ma.waveform_set_frequency(&wave, pitch.a * 0.5)
				case .PERIOD:
					ma.waveform_set_frequency(&wave, pitch.b * 0.5)
				case .SLASH:
					ma.waveform_set_frequency(&wave, pitch.c * 0.5)
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
		if any_key_pressed() {
			start_device(&device)
		} else {
			stop_device(&device)
		}

		// Render
		// sdl2.RenderPresent(renderer)
		// sdl2.SetRenderDrawColor(renderer, 0, 0, 0, 255)
		// sdl2.RenderClear(renderer)

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
