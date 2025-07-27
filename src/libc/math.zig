const abi = @import("abi");

pub export fn abs(num: c_int) callconv(.c) c_int {
    // abi.sys.log("abs()");
    return @intCast(@abs(num));
}

// pub export fn fabs(num: f32) callconv(.c) f32 {
//     abi.sys.log("fabs()");
//     return @abs(num);
// }
