const abi = @import("abi");
const std = @import("std");

//

pub export fn strcasecmp(lhs: [*c]const u8, rhs: [*c]const u8) callconv(.c) c_int {
    // abi.sys.log("strcasecmp()");
    return strncasecmp(lhs, rhs, std.math.maxInt(c_ulong));
}

pub export fn strncasecmp(lhs: [*c]const u8, rhs: [*c]const u8, num: c_ulong) callconv(.c) c_int {
    // abi.sys.log("strncasecmp()");
    for (0..num) |n| {
        const l = std.ascii.toLower(lhs[n]);
        const r = std.ascii.toLower(rhs[n]);

        if (l == 0 and r == 0) break;
        if (l != r or l == 0 or r == 0) {
            return @as(c_int, l) - @as(c_int, r);
        }
    }

    return 0;
}

test "strcasecmp/strncasecmp" {
    try std.testing.expectEqual(0, strcasecmp("a\x00", "a\x00"));
    try std.testing.expectEqual(0, strcasecmp("a\x00", "A\x00"));
    try std.testing.expectEqual(-49, strcasecmp("a\x00", "a1\x00"));
    try std.testing.expectEqual(-49, strcasecmp("a\x00", "A1\x00"));
    try std.testing.expectEqual(49, strcasecmp("a1\x00", "a\x00"));
    try std.testing.expectEqual(0, strcasecmp("\x00", "\x00"));
    try std.testing.expectEqual(0, strcasecmp("", ""));
    try std.testing.expectEqual(0, strncasecmp("test", "test", 4));
    try std.testing.expectEqual(0, strncasecmp("teSt", "tEsT", 4));
    try std.testing.expectEqual(-1, strncasecmp("test1", "test2", 5));
    try std.testing.expectEqual(-1, strncasecmp("test1", "Test2", 5));
    try std.testing.expectEqual(0, strncasecmp("test", "TEST", 4));
    try std.testing.expectEqual(0, strncasecmp("test", "yeet", 0));
    try std.testing.expectEqual(0, strncasecmp("test", "test", 2000));
}
