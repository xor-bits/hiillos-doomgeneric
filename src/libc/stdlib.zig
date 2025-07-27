const abi = @import("abi");
const std = @import("std");

const errno = @import("errno.zig");

//

pub export fn malloc(size: c_ulong) callconv(.c) [*c]u8 {
    if (abi.mem.slab_allocator.alloc(u8, size + 16)) |ptr| {
        const metadata: *usize = @alignCast(@ptrCast(ptr.ptr));
        metadata.* = size;

        return ptr[16..].ptr;
    } else |err| {
        errno.errno = errno.asErrno(err);
        return null;
    }
}

pub export fn realloc(old_ptr: [*]u8, size: c_ulong) callconv(.c) [*c]u8 {
    const real_ptr: [*]u8 = @ptrFromInt(@intFromPtr(old_ptr) - 16);
    const old_metadata: *usize = @alignCast(@ptrCast(real_ptr));

    if (abi.mem.slab_allocator.realloc(real_ptr[0..old_metadata.*], size)) |ptr| {
        const metadata: *usize = @alignCast(@ptrCast(ptr.ptr));
        metadata.* = size;

        return ptr[16..].ptr;
    } else |err| {
        errno.errno = errno.asErrno(err);
        return null;
    }
}

pub export fn calloc(num: c_ulong, _size: c_ulong) callconv(.c) [*c]u8 {
    const size = num * _size;

    if (abi.mem.slab_allocator.alloc(u8, size + 16)) |ptr| {
        const metadata: *usize = @alignCast(@ptrCast(ptr.ptr));
        metadata.* = size;

        std.crypto.secureZero(u8, ptr[16..]);
        return ptr[16..].ptr;
    } else |err| {
        errno.errno = errno.asErrno(err);
        return null;
    }
}

pub export fn free(ptr: [*]u8) callconv(.c) void {
    const real_ptr: [*]u8 = @ptrFromInt(@intFromPtr(ptr) - 16);
    const metadata: *usize = @alignCast(@ptrCast(real_ptr));

    abi.mem.slab_allocator.free(real_ptr[0..metadata.*]);
}

pub export fn atoi(str: [*c]const u8) callconv(.c) c_int {
    const input = std.mem.trimLeft(u8, std.mem.span(str), " \t\n");
    var current: c_int = 0;
    while (true) current = std.fmt.parseInt(c_int, input, 0) catch break;
    return current;
}

pub export fn atof(str: [*c]const u8) callconv(.c) f32 {
    const input = std.mem.trimLeft(u8, std.mem.span(str), " \t\n");
    var current: f32 = 0.0;
    while (true) current = std.fmt.parseFloat(f32, input) catch break;
    return current;
}

pub export fn exit(exit_code: c_int) callconv(.c) noreturn {
    _ = exit_code; // autofix
    unreachable;
}

pub export fn system(command: [*c]const u8) callconv(.c) c_int {
    _ = command; // autofix
    unreachable;
}
