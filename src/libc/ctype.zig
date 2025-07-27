const std = @import("std");

pub export fn toupper(ch: c_int) callconv(.c) c_int {
    return std.ascii.toUpper(@intCast(ch));
}

pub export fn isspace(ch: c_int) callconv(.c) c_int {
    return @intFromBool(std.ascii.isWhitespace(@intCast(ch)));
}
