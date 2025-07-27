pub export fn abs(num: c_int) callconv(.c) c_int {
    return @intCast(@abs(num));
}

// pub export fn fabs(num: f32) callconv(.c) f32 {
//     return @abs(num);
// }
