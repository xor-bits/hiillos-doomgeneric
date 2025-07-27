const abi = @import("abi");
const std = @import("std");

pub export fn toupper(ch: c_int) callconv(.c) c_int {
    // abi.sys.log("toupper()");
    // std.log.debug("toupper({})", .{ch});
    if (std.math.cast(u8, ch)) |byte| {
        return std.ascii.toUpper(byte);
    } else {
        return ch;
    }
}

pub export fn isspace(ch: c_int) callconv(.c) c_int {
    // abi.sys.log("isspace()");
    // std.log.debug("isspace({})", .{ch});
    return @intFromBool(std.ascii.isWhitespace(@intCast(ch)));
}
