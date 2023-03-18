package setup

import "core:os"
import "core:fmt"
import "core:path/filepath"


// could use os.read_entire_file, os.write_entire_file, but going more into
// details here was helpful for learning how things work
copy_file_for_learning :: proc(src, dst: string) -> (success: bool) {
	if os.is_file(dst) {
		fmt.println(dst, "already exists, skipping copy")
		return true
	}
	if !os.exists(src) {
		fmt.eprintln("ERROR: No source dll file found at:", src)
		return false
	}
	fmt.println("copying", src, "->", dst)

	src_handle, src_open_err := os.open(src, os.O_RDONLY)
	fmt.println("opened src file with err:", src_open_err)
	if src_open_err != os.ERROR_NONE do return false
	defer {
		src_close_err := os.close(src_handle)
		fmt.println("closed src file with err:", src_close_err)
	}

	dst_handle, dst_open_err := os.open(dst, os.O_WRONLY | os.O_CREATE)
	fmt.println("opened dst file with err:", dst_open_err)
	if dst_open_err != os.ERROR_NONE do return false
	defer {
		dst_close_err := os.close(dst_handle)
		fmt.println("closed dst file with err:", dst_close_err)
	}

	buf: [32]byte
	for {
		amount_read, read_err := os.read(src_handle, buf[:])
		fmt.printf("read %d bytes %v %s with err: %v\n", amount_read, buf, buf, read_err)
		if read_err != os.ERROR_NONE do break
		to_write := buf[:amount_read]
		amount_written, write_err := os.write(dst_handle, to_write)
		fmt.printf(
			"wrote %d bytes %v %s with err: %v\n",
			amount_written,
			to_write,
			to_write,
			write_err,
		)
		if write_err != os.ERROR_NONE do return false
		if amount_read == 0 do break
	}

	return true
}

copy_file :: proc(src, dst: string) -> (success: bool) {
	data, read_ok := os.read_entire_file(src)
	if !read_ok do return false
	write_ok := os.write_entire_file(dst, data)
	return write_ok
}

// Copy dll files from odin install to the project folder
// This avoids having to commit all of these to git for the project to work
// (.dll only tested on Windows, maybe .lib are needed on other platforms)
main :: proc() {
	exe_path := os.args[0]

	project_root := filepath.dir(exe_path)
	fmt.println("project root:", project_root)

	sdl2_dir := filepath.join({ODIN_ROOT, "vendor", "sdl2"})
	fmt.println("sdl2 dir:", sdl2_dir)

	{
		files := [?]string{"SDL2.dll"}
		for file in files {
			src := filepath.join({sdl2_dir, file})
			dst := filepath.join({project_root, file})
			err := copy_file(src, dst)
			fmt.println("copy ok:", err)
		}
	}

	{
		ttf_path := filepath.join({sdl2_dir, "ttf"})
		files := [?]string{"libfreetype-6.dll", "SDL2_ttf.dll", "zlib1.dll"}
		for file in files {
			src := filepath.join({ttf_path, file})
			dst := filepath.join({project_root, file})
			err := copy_file(src, dst)
			fmt.println("copy ok:", err)
		}
	}
}
