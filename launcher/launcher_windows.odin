package launcher

import "core:c"
import "core:fmt"
import win32 "core:sys/windows"
import "vendor:sdl2"

rect_overlap_area :: proc(a, b: ^sdl2.Rect) -> int {
	if sdl2.HasIntersection(a, b) {
		result: sdl2.Rect
		sdl2.IntersectRect(a, b, &result)
		return int(result.w * result.h)
	}
	return 0
}

get_active_display_index :: proc() -> c.int {
	mf_win := sdl2.GetMouseFocus()
	fmt.println("mouse focus:", mf_win)
	kf_win := sdl2.GetKeyboardFocus()
	fmt.println("keyboard focus:", kf_win)
	// These are both <nil> :(

	foreground_rect_found := false
	foreground_rect: sdl2.Rect
	when ODIN_OS == .Windows {
		fmt.println("running on windows")
		rect: win32.RECT
		handle := win32.GetForegroundWindow()
		err := win32.GetWindowRect(handle, &rect)
		fmt.println("handle:", handle, "rect:", rect, "error:", err)
		if err {
			// It errors with 6 (The handle is invalid), but the rect gets the
			// right values, so it seems to have worked?
			fmt.println("Error getting window rect", win32.GetLastError())
		}
		foreground_rect_found = true
		foreground_rect.x = rect.left
		foreground_rect.y = rect.top
		foreground_rect.w = rect.right - rect.left
		foreground_rect.h = rect.bottom - rect.top
	}
	if !foreground_rect_found {
		return 0
	}
	fmt.println("foreground rect:", foreground_rect)

	// Check which display contains the window with focus
	display_count := sdl2.GetNumVideoDisplays()
	active: c.int = 0
	max_overlap := 0
	for i: c.int = 0; i < display_count; i += 1 {
		rect: sdl2.Rect
		err := sdl2.GetDisplayBounds(i, &rect)
		if err != 0 do continue
		fmt.println(i, rect)
		overlap_area := rect_overlap_area(&rect, &foreground_rect)
		fmt.printf("monitor %d has overlap of %d\n", i, overlap_area)
		if overlap_area > max_overlap {
			active = i
			max_overlap = overlap_area
		}
	}
	return active
}
