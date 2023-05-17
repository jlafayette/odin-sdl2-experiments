package game

import "core:time"
import "core:fmt"
import ma "vendor:miniaudio"

Sound :: enum {
	BLEEP,
	BLOOP,
	BREAKOUT,
	POWERUP,
	SOLID,
}

_Sound :: struct {
	sound:      ma.sound,
	start_time: time.Time,
}

@(private = "file")
_sounds: [5][]_Sound
@(private = "file")
_chan_per_sound: [5]int = {2, 2, 1, 1, 2}
@(private = "file")
_sound_files: [5]cstring = {
	"breakout/audio/bleep.mp3",
	"breakout/audio/bloop.wav",
	"breakout/audio/breakout.mp3",
	"breakout/audio/powerup.wav",
	"breakout/audio/solid.wav",
}
@(private = "file")
_engine: ma.engine

sound_engine_init :: proc() -> bool {
	result := ma.engine_init(nil, &_engine)
	if result != ma.result.SUCCESS {
		fmt.eprintf("Unable to initialize audio engine: %v\n", result)
		return false
	}
	for file, i in _sound_files {
		_sounds[i] = make([]_Sound, _chan_per_sound[i])
		for j := 0; j < _chan_per_sound[i]; j += 1 {
			result = ma.sound_init_from_file(
				&_engine,
				file,
				cast(u32)ma.sound_flags.DECODE,
				nil,
				nil,
				&_sounds[i][j].sound,
			)
			if result != ma.result.SUCCESS {
				fmt.eprintf("Error loading %s: %v\n", file, result)
				return false
			}

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
	result: ma.result
	for _, i in _sounds[sound] {
		s: ^_Sound = &_sounds[sound][i]
		if !ma.sound_is_playing(&s.sound) {
			result = ma.sound_start(&s.sound)
			s.start_time = time.now()
			fmt.printf("started %v on chan %d\n", sound, i)
			return
		}
	}
	now := time.now()
	max: time.Duration = 0
	max_s: ^_Sound = &_sounds[sound][0]
	max_i: int = 0
	for _, i in _sounds[sound] {
		s: ^_Sound = &_sounds[sound][i]
		since := time.diff(s.start_time, now)
		if since > max {
			max = since
			max_s = s
			max_i = i
		}
	}
	result = ma.sound_seek_to_pcm_frame(&max_s.sound, 0)
	result = ma.sound_start(&max_s.sound)
	max_s.start_time = now
	fmt.printf("(FULL) started %v on chan %d\n", sound, max_i)
}
