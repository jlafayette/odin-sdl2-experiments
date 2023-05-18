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

_SoundTime :: struct {
	sound:      ma.sound,
	start_time: time.Time,
}

@(private = "file")
_sounds: [5][]_SoundTime
@(private = "file")
_chan_per_sound: [5]int = {4, 2, 1, 1, 2}
@(private = "file")
_sound_files: [5]cstring = {
	"breakout/audio/bleep.mp3",
	"breakout/audio/bloop.wav",
	"breakout/audio/breakout.mp3",
	"breakout/audio/powerup.wav",
	"breakout/audio/solid.wav",
}
@(private = "file")
_preloaded_sounds: [5]ma.sound
@(private = "file")
_engine: ma.engine
@(private = "file")
sound_load :: proc(type: Sound, sound: ^ma.sound) -> bool {
	result := ma.sound_init_from_file(
		&_engine,
		_sound_files[type],
		cast(u32)ma.sound_flags.DECODE,
		nil,
		nil,
		sound,
	)
	if result != ma.result.SUCCESS {
		fmt.eprintf("Error loading %s: %v\n", _sound_files[type], result)
		return false
	}
	return true
}

sound_engine_init :: proc() -> bool {
	result := ma.engine_init(nil, &_engine)
	if result != ma.result.SUCCESS {
		fmt.eprintf("Unable to initialize audio engine: %v\n", result)
		return false
	}
	for type in Sound {
		ok := sound_load(type, &_preloaded_sounds[type])
		if !ok do return false
		_sounds[type] = make([]_SoundTime, _chan_per_sound[type])
		for j := 0; j < _chan_per_sound[type]; j += 1 {
			sound_load(type, &_sounds[type][j].sound)
		}
	}
	return true
}
sound_engine_destroy :: proc() {
	for items in _sounds {
		delete(items)
	}
	for s in &_preloaded_sounds {
		ma.sound_uninit(&s)
	}
	ma.engine_uninit(&_engine)
}

music_play :: proc(music: Sound) {
	s: ^ma.sound = &_sounds[music][0].sound
	ma.sound_set_looping(s, true)
	ma.sound_start(s)
}

sound_play :: proc(sound: Sound, volume: f32 = 1, pan: f32 = 0, pitch: f32 = 1) {
	result: ma.result
	for _, i in _sounds[sound] {
		s: ^_SoundTime = &_sounds[sound][i]
		if !ma.sound_is_playing(&s.sound) {
			ma.sound_set_volume(&s.sound, volume)
			ma.sound_set_pan(&s.sound, pan)
			ma.sound_set_pitch(&s.sound, pitch)
			result = ma.sound_start(&s.sound)
			s.start_time = time.now()
			// fmt.printf("started %v on chan %d\n", sound, i)
			// fmt.printf("volume: %.2f, pitch: %.2f, pan: %.2f\n", volume, pitch, pan)
			return
		}
	}
	now := time.now()
	max: time.Duration = 0
	max_s: ^_SoundTime = &_sounds[sound][0]
	max_i: int = 0
	for _, i in _sounds[sound] {
		s: ^_SoundTime = &_sounds[sound][i]
		since := time.diff(s.start_time, now)
		if since > max {
			max = since
			max_s = s
			max_i = i
		}
	}
	result = ma.sound_seek_to_pcm_frame(&max_s.sound, 0)
	ma.sound_set_volume(&max_s.sound, volume)
	ma.sound_set_pan(&max_s.sound, pan)
	ma.sound_set_pitch(&max_s.sound, pitch)
	result = ma.sound_start(&max_s.sound)
	max_s.start_time = now
	// fmt.printf("(FULL) started %v on chan %d\n", sound, max_i)
}
