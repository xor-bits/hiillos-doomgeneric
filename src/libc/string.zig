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

pub export fn strlen(str: [*c]const u8) callconv(.c) c_ulong {
    return std.mem.span(str).len;
}

pub export fn strcmp(lhs: [*c]const u8, rhs: [*c]const u8) callconv(.c) c_int {
    var n: usize = 0;

    while (true) {
        const l = lhs[n];
        const r = rhs[n];
        n += 1;

        if (l == 0 and r == 0) return 0;
        if (l == 0) return -1;
        if (r == 0) return 1;

        if (l < r) {
            return -1;
        } else if (l == r) {
            continue;
        } else {
            return 1;
        }
    }
}

pub export fn strncpy(dst: [*c]u8, src: [*c]const u8, num: c_ulong) callconv(.c) [*c]u8 {
    _ = dst; // autofix
    _ = src; // autofix
    _ = num; // autofix
    unreachable;
}

pub export fn strncmp(lhs: [*c]const u8, rhs: [*c]const u8, num: c_ulong) callconv(.c) c_int {
    _ = lhs; // autofix
    _ = rhs; // autofix
    _ = num; // autofix
    unreachable;
}

pub export fn strstr(src: [*c]const u8, substr: [*c]const u8) callconv(.c) [*c]const u8 {
    _ = src; // autofix
    _ = substr; // autofix
    unreachable;
}

pub export fn strdup(src: [*c]const u8) callconv(.c) [*c]u8 {
    if (abi.mem.slab_allocator.dupeZ(u8, std.mem.span(src))) |ptr| {
        return ptr;
    } else |err| {
        errno.errno = errno.asErrno(err);
        return null;
    }
}

pub export fn strchr(str: [*c]u8, ch: c_int) callconv(.c) [*c]u8 {
    _ = str; // autofix
    _ = ch; // autofix
    unreachable;
}

pub export fn strrchr(str: [*c]u8, ch: c_int) callconv(.c) [*c]u8 {
    _ = str; // autofix
    _ = ch; // autofix
    unreachable;
}
