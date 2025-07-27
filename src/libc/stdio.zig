const std = @import("std");
const abi = @import("abi");

const errno = @import("errno.zig");

const seek_set = 0;
const seek_cur = 1;
const seek_end = 2;

pub const File = struct {
    file: ?abi.caps.Frame = null,
    reader: ?abi.io.File = null,
    writer: ?abi.io.File = null,
    read: ?std.io.BufferedReader(0x1000, abi.io.File.Reader) = null,
    write: ?std.io.BufferedWriter(0x1000, abi.io.File.Writer) = null,
};

var stderr_file = File{
    .write = std.io.bufferedWriter(abi.io.stderr.writer()),
};
pub export var stderr: *File = &stderr_file;

var stdout_file = File{
    .write = std.io.bufferedWriter(abi.io.stdout.writer()),
};
pub export var stdout: *File = &stdout_file;

pub export fn puts(str: [*c]const u8) callconv(.c) c_int {
    stdout.write.?.writer().print("{s}\n", .{str}) catch {
        return -1;
    };
    return 0;
}

pub export fn putchar(ch: c_int) callconv(.c) c_int {
    stdout.write.?.writer().writeByte(@intCast(ch)) catch {
        return -1;
    };
    return 0;
}

pub export fn fprintf(stream: ?*File, format: [*c]const u8, ...) callconv(.c) c_int {
    var args = @cVaStart();
    defer @cVaEnd(&args);
    return vfprintf(stream, format, &args);
}

fn vaPrintf(
    stream: ?*File,
    format: [*c]const u8,
    append_null: bool,
    args: *std.builtin.VaList,
) !usize {
    const s = stream orelse return 0;
    const buf_writer = &(s.write orelse return 0);
    var counting_writer = std.io.countingWriter(buf_writer.writer());
    const writer = counting_writer.writer();

    var fmt: []const u8 = std.mem.span(format);

    while (true) {
        if (fmt.len == 0) break;
        try fmtNext(
            &fmt,
            writer,
            args,
        );
    }

    if (append_null) {
        try writer.writeByte('\x00');
    }

    try buf_writer.flush();
    return counting_writer.bytes_written;
}

fn fmtNext(
    fmt: *[]const u8,
    writer: anytype,
    args: *std.builtin.VaList,
) !void {
    const State = enum {
        start,
        flags,
        min_width,
        init_precision,
        precision,
        length_modifier1,
        length_modifier2,
        conversion,
    };

    var ch = fmtPopChar(fmt) orelse return;

    var left_justified = false;
    var sign = false;
    var space = false;
    var alternative = false;
    var leading_zeros = false;
    var min_width: ?usize = null;
    var precision: ?usize = null;
    var length_modifier: enum {
        none,
        h,
        hh,
        l,
        ll,
        j,
        z,
        t,
        L,
    } = .none;

    loop: switch (State.start) {
        .start => switch (ch) {
            '%' => {
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .flags;
            },
            else => {
                try writer.writeByte(ch);
                return;
            },
        },
        .flags => switch (ch) {
            '%' => {
                try writer.writeByte('%');
                return;
            },
            '-' => {
                left_justified = true;
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .flags;
            },
            '+' => {
                sign = true;
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .flags;
            },
            ' ' => {
                space = true;
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .flags;
            },
            '#' => {
                alternative = true;
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .flags;
            },
            '0' => {
                leading_zeros = true;
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .flags;
            },
            else => continue :loop .min_width,
        },
        .min_width => switch (ch) {
            '0'...'9' => {
                if (min_width == null) min_width = 0;
                min_width.? *= 10;
                min_width.? = ch - '0';

                ch = fmtPopChar(fmt) orelse return;
                continue :loop .min_width;
            },
            '*' => {
                const arg = @cVaArg(args, c_int);
                if (arg < 0) left_justified = true;
                min_width = @abs(arg);

                ch = fmtPopChar(fmt) orelse return;
                continue :loop .init_precision;
            },
            else => continue :loop .init_precision,
        },
        .init_precision => switch (ch) {
            '.' => {
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .precision;
            },
            else => continue :loop .length_modifier1,
        },
        .precision => switch (ch) {
            '0'...'9' => {
                if (precision == null) precision = 0;
                precision.? *= 10;
                precision.? = ch - '0';

                ch = fmtPopChar(fmt) orelse return;
                continue :loop .precision;
            },
            '*' => {
                const arg = @cVaArg(args, c_int);
                if (arg < 0) {
                    ch = fmtPopChar(fmt) orelse return;
                    continue :loop .length_modifier1;
                }
                precision = @intCast(arg);

                ch = fmtPopChar(fmt) orelse return;
                continue :loop .length_modifier1;
            },
            else => continue :loop .length_modifier1,
        },
        .length_modifier1 => switch (ch) {
            'h' => {
                length_modifier = .h;
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .length_modifier2;
            },
            'l' => {
                length_modifier = .l;
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .length_modifier2;
            },
            'j' => {
                length_modifier = .j;
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .conversion;
            },
            'z' => {
                length_modifier = .z;
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .conversion;
            },
            't' => {
                length_modifier = .t;
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .conversion;
            },
            'L' => {
                length_modifier = .L;
                ch = fmtPopChar(fmt) orelse return;
                continue :loop .conversion;
            },
            else => continue :loop .conversion,
        },
        .length_modifier2 => switch (ch) {
            'h' => switch (length_modifier) {
                .h => {
                    length_modifier = .hh;
                    ch = fmtPopChar(fmt) orelse return;
                    continue :loop .conversion;
                },
                else => continue :loop .conversion,
            },
            'l' => switch (length_modifier) {
                .l => {
                    length_modifier = .ll;
                    ch = fmtPopChar(fmt) orelse return;
                    continue :loop .conversion;
                },
                else => continue :loop .conversion,
            },
            else => continue :loop .conversion,
        },
        .conversion => switch (ch) {
            'c' => switch (length_modifier) {
                .none => {
                    try writer.writeByte(@intCast(@cVaArg(args, c_int)));
                    return;
                },
                .l => {
                    try writer.writeByte(@intCast(@cVaArg(args, c_uint)));
                    return;
                },
                else => return abi.sys.Error.InvalidArgument,
            },
            's' => switch (length_modifier) {
                .none => {
                    const ptr = @cVaArg(args, [*c]const u8);
                    const str: []const u8 = if (precision) |prec|
                        std.mem.sliceTo(ptr[0..prec], 0)
                    else
                        std.mem.span(ptr);

                    try writer.writeAll(str);
                    return;
                },
                .l => {
                    if (true) unreachable;

                    const ptr = @cVaArg(args, [*c]const u16);
                    const str: []const u16 = if (precision) |prec|
                        std.mem.sliceTo(ptr[0..prec], 0)
                    else
                        std.mem.span(ptr);

                    var it = std.unicode.Utf16LeIterator.init(str);
                    while (it.nextCodepoint() catch {
                        return abi.sys.Error.InvalidArgument;
                    }) |codepoint| {
                        var out: [8]u8 = undefined;
                        const len = std.unicode.utf8Encode(codepoint, &out) catch {
                            return abi.sys.Error.InvalidArgument;
                        };

                        try writer.writeAll(out[0..len]);
                    }
                    return;
                },
                else => return abi.sys.Error.InvalidArgument,
            },
            'x' => switch (length_modifier) {
                .none => {
                    try std.fmt.formatInt(@cVaArg(args, c_uint), 16, .lower, .{
                        .alignment = if (left_justified) .left else .right,
                        .fill = if (space) ' ' else if (leading_zeros) '0' else ' ',
                        .precision = precision,
                        .width = if (!space and !leading_zeros) null else min_width,
                    }, writer);
                },
                else => return abi.sys.Error.InvalidArgument,
            },
            'p' => {
                const ptr = @cVaArg(args, ?*anyopaque);
                try writer.print("0x{x}", .{@intFromPtr(ptr)});
            },
            else => {
                std.log.err("vaPrintf unimplemented: {c}", .{ch});
                return abi.sys.Error.Unimplemented;
            },
        },
    }
}

fn fmtPrint(
    count: *usize,
    writer: anytype,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    try writer.print(fmt, .args);
    count.* += std.fmt.count(fmt, args);
}

fn fmtPopChar(fmt: *[]const u8) ?u8 {
    if (fmt.*.len == 0) return null;
    const ch = fmt.*[0];
    fmt.* = fmt.*[1..];
    return ch;
}

pub export fn vfprintf(stream: ?*File, format: [*c]const u8, args: *std.builtin.VaList) callconv(.c) c_int {
    const count = vaPrintf(
        stream,
        format,
        false,
        args,
    ) catch |err| switch (err) {
        error.InvalidState => {
            errno.errno = errno.asErrno(abi.sys.Error.BadHandle);
            return -1;
        },
        error.Full => unreachable,
        else => {
            errno.errno = errno.asErrno(@errorCast(err));
            return -1;
        },
    };
    return @intCast(count);
}

pub export fn printf(format: [*c]const u8, ...) callconv(.c) c_int {
    var args = @cVaStart();
    defer @cVaEnd(&args);
    return vprintf(format, &args);
}

pub export fn vprintf(format: [*c]const u8, args: *std.builtin.VaList) callconv(.c) c_int {
    return vfprintf(stdout, format, args);
}

pub export fn snprintf(s: [*c]u8, n: c_ulong, format: [*c]const u8, ...) callconv(.c) c_int {
    var args = @cVaStart();
    defer @cVaEnd(&args);
    return vsnprintf(s, n, format, &args);
}

pub export fn vsnprintf(s: [*c]u8, n: c_ulong, format: [*c]const u8, args: *std.builtin.VaList) callconv(.c) c_int {
    _ = s; // autofix
    _ = n; // autofix
    _ = format; // autofix
    _ = args; // autofix
    unreachable;
}

pub export fn sscanf(s: [*c]const u8, format: [*c]const u8, ...) callconv(.c) c_int {
    var args = @cVaStart();
    defer @cVaEnd(&args);
    return vsscanf(s, format, &args);
}

pub export fn vsscanf(s: [*c]const u8, format: [*c]const u8, args: *std.builtin.VaList) callconv(.c) c_int {
    _ = s; // autofix
    _ = format; // autofix
    _ = args; // autofix
    unreachable;
}

pub fn unixPathAsUri(pathname: []const u8) !abi.fs.Path {
    std.log.info("unixPathAsUri({s})", .{pathname});

    var path: abi.caps.Frame = undefined;
    var path_len: usize = undefined;
    if (std.fs.path.isAbsolute(pathname)) {
        std.log.info("unixPathAsUri is absolute", .{});
        path_len = "initfs://".len + pathname.len;
        path = try abi.caps.Frame.create(path_len);
        errdefer path.close();

        var path_stream = path.stream();
        try path_stream.writer().print("initfs://{s}", .{pathname});
        std.debug.assert(path_stream.read == 0);
        std.debug.assert(path_stream.write == path_len);
    } else {
        var args = abi.process.args();
        const cmd = args.next().?;
        const cmd_dir = std.fs.path.dirname(cmd).?;
        std.log.info("unixPathAsUri is relative to {s}", .{cmd_dir});

        path_len = cmd_dir.len + 1 + pathname.len;
        path = try abi.caps.Frame.create(path_len);
        errdefer path.close();

        var path_stream = path.stream();
        try path_stream.writer().print("{s}/{s}", .{ cmd_dir, pathname });
        std.debug.assert(path_stream.read == 0);
        std.debug.assert(path_stream.write == path_len);
    }

    return .{ .long = .{
        .frame = path,
        .offs = 0,
        .len = path_len,
    } };
}

pub export fn fopen(filename: [*c]const u8, mode: [*c]const u8) callconv(.c) ?*File {
    const filename_str: []const u8 = std.mem.span(filename);
    const mode_str: []const u8 = std.mem.span(mode);

    const path = unixPathAsUri(filename_str) catch |err| {
        errno.errno = errno.asErrno(err);
        return null;
    };

    const has_r = std.mem.containsAtLeastScalar(u8, mode_str, 1, 'r');
    const has_w = std.mem.containsAtLeastScalar(u8, mode_str, 1, 'w');
    const has_a = std.mem.containsAtLeastScalar(u8, mode_str, 1, 'a');
    const has_p = std.mem.containsAtLeastScalar(u8, mode_str, 1, '+');
    // const has_b = std.mem.containsAtLeastScalar(u8, mode_str, 1, 'b');

    const open_mode: enum { r, w, a, rp, wp, ap } = if (has_r and !has_p)
        .r
    else if (has_w and !has_p)
        .w
    else if (has_a and !has_p)
        .a
    else if (has_r)
        .rp
    else if (has_w)
        .wp
    else if (has_a)
        .ap
    else {
        path.deinit();
        errno.errno = errno.asErrno(abi.sys.Error.InvalidArgument);
        return null;
    };
    const open_opts: abi.fs.OpenOptions = switch (open_mode) {
        .r => .{
            .mode = .read_only,
            .file_policy = .use_existing,
            .dir_policy = .use_existing,
        },
        .w => .{
            .mode = .write_only,
            .file_policy = .create_if_missing,
            .dir_policy = .use_existing,
        },
        .a => .{
            .mode = .write_only,
            .file_policy = .create_if_missing,
            .dir_policy = .use_existing,
        },
        .rp => .{
            .mode = .read_write,
            .file_policy = .use_existing,
            .dir_policy = .use_existing,
        },
        .wp => .{
            .mode = .read_write,
            .file_policy = .create_if_missing,
            .dir_policy = .use_existing,
        },
        .ap => .{
            .mode = .read_write,
            .file_policy = .create_if_missing,
            .dir_policy = .use_existing,
        },
    };

    const file_resp = abi.lpc.call(
        abi.VfsProtocol.OpenFileRequest,
        .{ .path = path, .open_opts = open_opts },
        abi.caps.COMMON_VFS,
    ) catch |err| {
        errno.errno = errno.asErrno(err);
        return null;
    };
    const file = file_resp.asErrorUnion() catch |err| {
        errno.errno = errno.asErrno(err);
        return null;
    };

    const fd = abi.mem.slab_allocator.create(File) catch |err| {
        file.close();
        errno.errno = errno.asErrno(err);
        return null;
    };

    fd.file = file;
    fd.reader = .{ .file = .{
        .frame = file,
        .cursor = .init(0),
    } };
    fd.writer = .{ .file = .{
        .frame = file,
        .cursor = .init(0),
    } };
    fd.read = std.io.bufferedReader(fd.reader.?.reader());
    fd.write = std.io.bufferedWriter(fd.writer.?.writer());

    return fd;
}

pub export fn fread(ptr: ?*anyopaque, size: c_ulong, count: c_ulong, stream: ?*File) callconv(.c) c_ulong {
    _ = ptr; // autofix
    _ = size; // autofix
    _ = count; // autofix
    _ = stream; // autofix
    unreachable;
}

pub export fn fwrite(ptr: ?*const anyopaque, size: c_ulong, count: c_ulong, stream: ?*File) callconv(.c) c_ulong {
    _ = ptr; // autofix
    _ = size; // autofix
    _ = count; // autofix
    _ = stream; // autofix
    unreachable;
}

pub export fn fseek(stream: ?*File, offset: c_long, origin: c_int) callconv(.c) c_int {
    _ = stream; // autofix
    _ = offset; // autofix
    _ = origin; // autofix
    unreachable;
}

pub export fn ftell(stream: ?*File) callconv(.c) c_int {
    _ = stream; // autofix
    unreachable;
}

pub export fn fflush(stream: ?*File) callconv(.c) c_int {
    _ = stream; // autofix
    unreachable;
}

pub export fn fclose(stream: ?*File) callconv(.c) c_int {
    _ = stream; // autofix
    unreachable;
}

pub export fn rename(old_filename: [*c]const u8, new_filename: [*c]const u8) callconv(.c) c_int {
    _ = old_filename; // autofix
    _ = new_filename; // autofix
    unreachable;
}

pub export fn remove(pathname: [*c]const u8) callconv(.c) c_int {
    _ = pathname; // autofix
    unreachable;
}
