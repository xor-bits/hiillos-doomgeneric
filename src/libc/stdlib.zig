const abi = @import("abi");
const std = @import("std");

const errno = @import("errno.zig");

//

const allocator = if (@import("builtin").is_test)
    std.testing.allocator
else
    abi.mem.slab_allocator;

pub export fn malloc(size: c_ulong) callconv(.c) [*c]u8 {
    // abi.sys.log("malloc()");
    if (allocator.alloc(u8, size + 16)) |ptr| {
        const metadata: *usize = @alignCast(@ptrCast(ptr.ptr));
        metadata.* = size;

        // std.log.err("malloc 0x{x} ({} b)", .{ @intFromPtr(ptr[16..].ptr), size });
        return ptr[16..].ptr;
    } else |err| {
        errno.errno = errno.asErrno(err);
        return null;
    }
}

pub export fn realloc(old_ptr: [*c]u8, size: c_ulong) callconv(.c) [*c]u8 {
    // abi.sys.log("realloc()");
    if (old_ptr == null) return malloc(size);

    const real_ptr: [*]u8 = @ptrFromInt(@intFromPtr(old_ptr) - 16);
    const old_metadata: *usize = @alignCast(@ptrCast(real_ptr));

    if (allocator.realloc(real_ptr[0..old_metadata.*], size)) |ptr| {
        const metadata: *usize = @alignCast(@ptrCast(ptr.ptr));
        metadata.* = size;

        // std.log.err("realloc 0x{x} ({} b)", .{ @intFromPtr(ptr[16..].ptr), size });
        return ptr[16..].ptr;
    } else |err| {
        errno.errno = errno.asErrno(err);
        return null;
    }
}

pub export fn calloc(num: c_ulong, _size: c_ulong) callconv(.c) [*c]u8 {
    // abi.sys.log("calloc()");
    const size = num * _size;

    if (allocator.alloc(u8, size + 16)) |ptr| {
        const metadata: *usize = @alignCast(@ptrCast(ptr.ptr));
        metadata.* = size;

        // std.log.err("calloc 0x{x} ({} b)", .{ @intFromPtr(ptr[16..].ptr), size });
        std.crypto.secureZero(u8, ptr[16..]);
        return ptr[16..].ptr;
    } else |err| {
        errno.errno = errno.asErrno(err);
        return null;
    }
}

pub export fn free(ptr: [*c]u8) callconv(.c) void {
    // abi.sys.log("free()");
    if (ptr == null) return;

    const real_ptr: [*]u8 = @ptrFromInt(@intFromPtr(ptr) - 16);
    const metadata: *usize = @alignCast(@ptrCast(real_ptr));

    // std.log.err("free 0x{x} ({} b)", .{ @intFromPtr(ptr), metadata.* });
    allocator.free(real_ptr[0 .. metadata.* + 16]);
}

pub export fn atoi(str: [*c]const u8) callconv(.c) c_int {
    // abi.sys.log("atoi()");
    const input = std.mem.trimLeft(u8, std.mem.span(str), " \t\n");
    var i: usize = input.len;
    while (i >= 1) : (i -= 1) {
        if (std.fmt.parseInt(c_int, input[0..i], 0)) |parsed| {
            return parsed;
        } else |_| {}
    }
    return 0;
}

test "atoi" {
    try std.testing.expectEqual(0, atoi(""));
    try std.testing.expectEqual(0, atoi("  "));
    try std.testing.expectEqual(1, atoi("  1"));
    try std.testing.expectEqual(1, atoi("  1  "));
    try std.testing.expectEqual(654, atoi("  654  "));
    try std.testing.expectEqual(654, atoi("  654  "));
    try std.testing.expectEqual(3, atoi(" 3d"));
    try std.testing.expectEqual(-3, atoi("-3d"));
    try std.testing.expectEqual(0, atoi("a-3d"));
    try std.testing.expectEqual(3, atoi("+3d"));
}

pub export fn atof(str: [*c]const u8) callconv(.c) f32 {
    // abi.sys.log("atof()");
    const input = std.mem.trimLeft(u8, std.mem.span(str), " \t\n");
    var i: usize = input.len;
    while (i >= 1) : (i -= 1) {
        if (std.fmt.parseFloat(f32, input[0..i])) |parsed| {
            return parsed;
        } else |_| {}
    }
    return 0.0;
}

pub export fn exit(exit_code: c_int) callconv(.c) noreturn {
    // abi.sys.log("exit()");
    abi.sys.selfStop(@as(u32, @bitCast(exit_code)));
}

pub export fn system(command: [*c]const u8) callconv(.c) c_int {
    // abi.sys.log("system()");
    // if (command == null) {
    //     return 0;
    // }
    // return -1;

    if (command == null) {
        return 1;
    }

    const cmd: [:0]const u8 = std.mem.span(command);

    return systemInner(cmd) catch |err| {
        errno.errno = errno.asErrno(err);
        return -1;
    };
}

fn systemInner(cmd: []const u8) !i32 {
    const prefix = "initfs:///sbin/sh\x00-c\x00";
    const arg_map = try abi.caps.Frame.create(prefix.len + cmd.len);
    var arg_map_stream = arg_map.stream();
    try arg_map_stream.writer().print("{s}{s}", .{
        prefix,
        cmd,
    });

    const env_map = try abi.caps.COMMON_ENV_MAP.clone();
    const stdio = try abi.io.stdio.clone();

    const result = try abi.lpc.call(abi.PmProtocol.ExecElfRequest, .{
        .arg_map = arg_map,
        .env_map = env_map,
        .stdio = stdio,
    }, abi.caps.COMMON_PM);
    const proc = try result.asErrorUnion();

    const exit_code = try proc.main_thread.wait();
    return @bitCast(@as(u32, @truncate(exit_code)));
}
