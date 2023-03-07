package color

import "core:math"

// Convert RGB
to_u8 :: proc(c: [3]f32) -> [3]u8 {
    d := c * 255
    return [3]u8{u8(math.round(d.r)), u8(math.round(d.g)), u8(math.round(d.b))}
}

// Adapted from https://github.com/lucasb-eyer/go-colorful
// Convert HSV (0-360, 0-1, 0-1) to RGB 0-1
hsv_to_rgb :: proc(hsv: [3]f32) -> [3]f32 {
    h, s, v := hsv.x, hsv.y, hsv.z
    Hp := h / 60.0
    C := v * s
    X := C * (1.0 - math.abs(math.mod(Hp, 2.0)-1.0))
    m := v - C
    c : [3]f32
    switch {
        case 0 <= Hp && Hp < 1:
            c.r = C
            c.g = X
        case 1 <= Hp && Hp < 2:
            c.r = X
            c.g = C
        case 2 <= Hp && Hp < 3:
            c.g = C
            c.b = X
        case 3 <= Hp && Hp < 4:
            c.g = X
            c.b = C
        case 4 <= Hp && Hp < 5:
            c.r = X
            c.b = C
        case 5 <= Hp && Hp <= 6:
            c.r = C
            c.b = X
    }
    return c + m
}
