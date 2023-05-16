package game

import "core:fmt"
import ma "vendor:miniaudio"

Sound :: enum {
	BLEEP,
	BLOOP,
	BREAKOUT,
	POWERUP,
	SOLID,
}
@(private = "file")
sounds: [5]ma.sound
@(private = "file")
sound_files: [5]cstring = {
	"breakout/audio/bleep.mp3",
	"breakout/audio/bloop.wav",
	"breakout/audio/breakout.mp3",
	"breakout/audio/powerup.wav",
	"breakout/audio/solid.wav",
}
@(private = "file")
engine: ma.engine

sound_engine_init :: proc() -> bool {
	result := ma.engine_init(nil, &engine)
	if result != ma.result.SUCCESS {
		fmt.eprintf("Unable to initialize audio engine: %v\n", result)
		return false
	}
	for file, i in sound_files {
		result = ma.sound_init_from_file(
			&engine,
			file,
			cast(u32)ma.sound_flags.DECODE,
			nil,
			nil,
			&sounds[i],
		)
		if result != ma.result.SUCCESS {
			fmt.eprintf("Error loading %s: %v\n", file, result)
			return false
		}
	}

	return true
}
sound_engine_destroy :: proc() {
	/*
	ma.engine_uninit(&engine)
	for _, i in sounds {
		ma.sound_uninit(&sounds[i])
	}
	*/
}

sound_play :: proc(sound: Sound) {
	s: ^ma.sound = &sounds[sound]
	result: ma.result
	if ma.sound_is_playing(s) {
		// could add multiple sounds to play more than one at once
		result = ma.sound_seek_to_pcm_frame(s, 0)
	} else {
		result = ma.sound_start(s)
	}
	// fmt.printf("started %v with result %v\n", sound, result)
}
