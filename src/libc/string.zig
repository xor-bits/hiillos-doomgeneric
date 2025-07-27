const abi = @import("abi");
const std = @import("std");

const errno = @import("errno.zig");

// pub export fn memset(ptr: ?*anyopaque, val: c_int, num: c_ulong) callconv(.c) ?*anyopaque {
//     _ = ptr; // autofix
//     _ = val; // autofix
//     _ = num; // autofix
//     unreachable;
// }

// pub export fn memcpy(dst: ?*anyopaque, src: ?*const anyopaque, num: c_ulong) callconv(.c) ?*anyopaque {
//     _ = dst; // autofix
//     _ = src; // autofix
//     _ = num; // autofix
//     unreachable;
// }

// pub export fn memmove(dst: ?*anyopaque, src: ?*const anyopaque, num: c_ulong) callconv(.c) ?*anyopaque {
//     _ = dst; // autofix
//     _ = src; // autofix
//     _ = num; // autofix
//     unreachable;
// }

pub export fn strncpy(dst: [*c]u8, src: [*c]const u8, num: c_ulong) callconv(.c) [*c]u8 {
    // abi.sys.log("strncpy()");
    for (0..num) |n| {
        const s = src[n];
        dst[n] = s;
        if (s == 0) break;
    }
    return dst;
}

pub export fn strlen(str: [*c]const u8) callconv(.c) c_ulong {
    // abi.sys.log("strlen()");
    return std.mem.span(str).len;
}

test "strlen" {
    try std.testing.expectEqual(strlen(""), 0);
    try std.testing.expectEqual(strlen("\x00"), 0);
    try std.testing.expectEqual(strlen("  \x00"), 2);
    try std.testing.expectEqual(strlen("  1\x00"), 3);
    try std.testing.expectEqual(strlen("  1  \x00"), 5);
    try std.testing.expectEqual(strlen("  654  \x00"), 7);
    try std.testing.expectEqual(strlen(" 3d\x00"), 3);
    try std.testing.expectEqual(strlen(" 3d\x00"), 3);
}

pub export fn strcmp(lhs: [*c]const u8, rhs: [*c]const u8) callconv(.c) c_int {
    // abi.sys.log("strcmp()");
    return strncmp(lhs, rhs, std.math.maxInt(c_ulong));
}

pub export fn strncmp(lhs: [*c]const u8, rhs: [*c]const u8, num: c_ulong) callconv(.c) c_int {
    // abi.sys.log("strncmp()");
    for (0..num) |n| {
        const l = lhs[n];
        const r = rhs[n];

        if (l == 0 and r == 0) break;
        if (l != r or l == 0 or r == 0) {
            return @as(c_int, l) - @as(c_int, r);
        }
    }

    return 0;
}

test "strcmp/strncmp" {
    try std.testing.expectEqual(0, strcmp("a\x00", "a\x00"));
    try std.testing.expectEqual(32, strcmp("a\x00", "A\x00"));
    try std.testing.expectEqual(-49, strcmp("a\x00", "a1\x00"));
    try std.testing.expectEqual(32, strcmp("a\x00", "A1\x00"));
    try std.testing.expectEqual(49, strcmp("a1\x00", "a\x00"));
    try std.testing.expectEqual(0, strcmp("\x00", "\x00"));
    try std.testing.expectEqual(0, strcmp("", ""));
    try std.testing.expectEqual(0, strncmp("test", "test", 4));
    try std.testing.expectEqual(32, strncmp("teSt", "tEsT", 4));
    try std.testing.expectEqual(-1, strncmp("test1", "test2", 5));
    try std.testing.expectEqual(32, strncmp("test1", "Test2", 5));
    try std.testing.expectEqual(32, strncmp("test", "TEST", 4));
    try std.testing.expectEqual(0, strncmp("test", "yeet", 0));
    try std.testing.expectEqual(0, strncmp("test", "test", 2000));
}

pub export fn strstr(src: [*c]const u8, substr: [*c]const u8) callconv(.c) [*c]const u8 {
    // abi.sys.log("strstr()");
    _ = src; // autofix
    _ = substr; // autofix
    unreachable;
}

pub export fn strdup(_src: [*c]const u8) callconv(.c) [*c]u8 {
    // abi.sys.log("strdup()");
    const src: [:0]const u8 = std.mem.span(_src);
    const alloc = @import("stdlib.zig").malloc(src.len + 1);
    if (alloc == null) return null;
    @memcpy(alloc, src);
    alloc[src.len] = 0;
    return alloc;
}

test "strdup" {
    const a: [*c]const u8 = "hello world";
    const b = strdup(a);
    defer @import("stdlib.zig").free(b);
    try std.testing.expectEqualSentinel(
        u8,
        0,
        std.mem.span(a),
        std.mem.span(b),
    );
}

pub export fn strchr(_str: [*c]u8, _ch: c_int) callconv(.c) [*c]u8 {
    // abi.sys.log("strchr()");
    const str_no_null: [:0]u8 = std.mem.span(_str);
    const str = str_no_null[0 .. str_no_null.len + 1];
    const ch: u8 = @bitCast(@as(i8, @truncate(_ch)));

    for (str, 0..) |b, i| {
        if (b == ch) return str[i..].ptr;
    }
    return null;
}

pub export fn strrchr(str: [*c]u8, ch: c_int) callconv(.c) [*c]u8 {
    // abi.sys.log("strrchr()");
    _ = str; // autofix
    _ = ch; // autofix
    unreachable;
}
