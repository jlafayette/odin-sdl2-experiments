package color

import "core:math"


toU8 :: proc(c: [3]f32) -> [3]u8 {
    d := c * 255
    return [3]u8{u8(math.round(d.r)), u8(math.round(d.g)), u8(math.round(d.b))}
}
