
package mixer

import "core:fmt"
import "core:mem"
import "core:os"
import "core:runtime"
import "core:strings"
import ma "vendor:miniaudio"

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	run()

	for _, leak in track.allocation_map {
		fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
	}
	for bad_free in track.bad_free_array {
		fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
	}
}


SAMPLE_FORMAT := ma.format.f32
CHANNEL_COUNT := 2
// SAMPLE_SIZE := ma.get_bytes_per_sample(SAMPLE_FORMAT)
// FRAME_SIZE := ma.get_bytes_per_frame(SAMPLE_FORMAT, u32(CHANNEL_COUNT))
SAMPLE_RATE := 48000
Decoder :: struct {
	decoder: ma.decoder,
	at_end:  bool,
}
decoders: [dynamic]Decoder
stop_event: ma.event

are_all_decoders_at_end :: proc "contextless" () -> bool {
	for _, i in decoders {
		if decoders[i].at_end == false {
			return false
		}
	}
	return true
}

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
	// 4096 is not the real length... just making up numbers
	// for this case it doesn't seem to matter since frame_count
	// is being used by all the mini-audio procedures
	out_slice := transmute([]f32)runtime.Raw_Slice{output, 4096}

	for _, i in decoders {
		decoder := &decoders[i]
		if !decoder.at_end {
			frames_read := read_and_mix_pcm_frames_f32(&decoder.decoder, out_slice, frame_count)
			if frames_read < frame_count {
				decoder.at_end = true
			}
		}
	}

	if are_all_decoders_at_end() {
		ma.event_signal(&stop_event)
	}
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

run :: proc() {
	reserve_dynamic_array(&decoders, 3)
	defer delete(decoders)

	config := ma.device_config_init(ma.device_type.playback)
	config.playback.format = SAMPLE_FORMAT
	config.playback.channels = u32(CHANNEL_COUNT)
	config.sampleRate = u32(SAMPLE_RATE)
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

	// mixing multiple decoders
	decoder_config := ma.decoder_config_init(SAMPLE_FORMAT, u32(CHANNEL_COUNT), u32(SAMPLE_RATE))

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
		append(&decoders, d)
	}

	if len(decoders) < 1 {
		fmt.eprintln("No sound files given!")
		return
	}

	// wait for the stop event (all done)
	ok := start_device(&device)
	if !ok {
		fmt.eprintln("ERROR starting device")
		return
	}
	ma.event_init(&stop_event)

	ma.event_wait(&stop_event)

	return
}
