const abi = @import("abi");
const std = @import("std");

const errno = @import("../errno.zig");
const stdio = @import("../stdio.zig");

//

pub const mode_t = c_int;

pub export fn mkdir(pathname: [*c]const u8, mode: mode_t) callconv(.c) c_int {
    const pathname_str: []const u8 = std.mem.span(pathname);
    _ = mode;

    const path = stdio.unixPathAsUri(pathname_str) catch |err| {
        errno.errno = errno.asErrno(err);
        return -1;
    };

    const result = abi.lpc.call(abi.VfsProtocol.OpenDirRequest, .{
        .path = path,
        .open_opts = .{ .mode = .read_only },
    }, abi.caps.COMMON_VFS) catch |err| {
        errno.errno = errno.asErrno(err);
        return -1;
    };

    const entries = result.asErrorUnion() catch |err| {
        errno.errno = errno.asErrno(err);
        return -1;
    };
    entries.data.close();

    return 0;
}
