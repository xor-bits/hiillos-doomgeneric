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
    // abi.sys.log("puts()");
    stdout.write.?.writer().print("{s}\n", .{str}) catch {
        return -1;
    };
    return 0;
}

pub export fn putchar(ch: c_int) callconv(.c) c_int {
    // abi.sys.log("putchar()");
    stdout.write.?.writer().writeByte(@intCast(ch)) catch {
        return -1;
    };
    return 0;
}

pub export fn fprintf(stream: ?*File, format: [*c]const u8, ...) callconv(.c) c_int {
    // abi.sys.log("fprintf()");
    var args = @cVaStart();
    defer @cVaEnd(&args);
    return vfprintf(stream, format, &args);
}

fn vaPrintf(
    _writer: anytype,
    format: [*c]const u8,
    args: *std.builtin.VaList,
) !usize {
    var stream = std.io.countingWriter(_writer);
    const writer = stream.writer();

    var fmt: []const u8 = std.mem.span(format);

    while (true) {
        if (fmt.len == 0) break;
        try fmtNext(
            &fmt,
            writer,
            args,
        );
    }

    return stream.bytes_written;
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
        print_sint,
        print_uint,
    };

    var ch = fmtPopChar(fmt) orelse return;

    var left_justified = false;
    var sign = false;
    var space = false;
    var alternative = false;
    var leading_zeros = false;
    var min_width: ?usize = null;
    var precision: ?usize = null;
    var length_modifier: LengthModifier = .none;

    var sint: i128 = 0;
    var uint: u128 = 0;
    var case: std.fmt.Case = .lower;
    var base: u8 = 0;

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
            'd', 'i' => {
                sint = try readSignedIntInput(
                    length_modifier,
                    args,
                );
                case = .lower;
                base = 10;
                continue :loop .print_sint;
            },
            'o' => {
                uint = try readUnsignedIntInput(
                    length_modifier,
                    args,
                );
                case = .lower;
                base = 8;
                // TODO: "In the alternative implementation precision is increased if
                // necessary, to write one leading zero. In that case if both the
                // converted value and the precision are ​0​, single ​0​ is written."
                continue :loop .print_uint;
            },
            'x', 'X' => {
                uint = try readUnsignedIntInput(
                    length_modifier,
                    args,
                );
                case = if (std.ascii.isUpper(ch)) .upper else .lower;
                base = 16;
                continue :loop .print_uint;
            },
            'u' => {
                uint = try readUnsignedIntInput(
                    length_modifier,
                    args,
                );
                case = .lower;
                base = 10;
                continue :loop .print_uint;
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
        .print_sint => {
            try fmtInt(
                writer,
                sint,
                left_justified,
                sign,
                space,
                alternative,
                leading_zeros,
                min_width,
                precision,
                case,
                base,
            );
            return;
        },
        .print_uint => {
            try fmtInt(
                writer,
                uint,
                left_justified,
                sign,
                space,
                alternative,
                leading_zeros,
                min_width,
                precision,
                case,
                base,
            );
            return;
        },
    }
}

const LengthModifier = enum {
    hh,
    h,
    none,
    l,
    ll,
    j,
    z,
    t,
    L,
};

fn fmtInt(
    writer: anytype,
    value: anytype,
    left_justified: bool,
    sign: bool,
    space: bool,
    alternative: bool,
    leading_zeros: bool,
    min_width: ?usize,
    _precision: ?usize,
    case: std.fmt.Case,
    base: u8,
) !void {
    // std.log.err(
    //     \\left_justified={any}
    //     \\sign={any}
    //     \\space={any}
    //     \\alternative={any}
    //     \\leading_zeros={any}
    //     \\min_width={any}
    //     \\precision={any}
    //     \\value={any}
    //     \\case={any}
    //     \\base={any}
    //     \\
    // , .{
    //     left_justified, sign,       space, alternative, leading_zeros,
    //     min_width,      _precision, value, case,        base,
    // });

    const prec = _precision orelse 1;

    if (value == 0 and prec == 0) return;
    const abs_value = @abs(value);

    // all digits
    const number_width: usize = if (value == 0) @max(prec, 1) else switch (base) {
        2 => @max(prec, std.math.log2_int(@TypeOf(abs_value), abs_value) + 1),
        10 => @max(prec, std.math.log10_int(abs_value) + 1),
        16 => @max(prec, std.math.log2_int(@TypeOf(abs_value), abs_value) / 4 + 1),
        else => unreachable,
    };
    // '-', '+' or ''
    const sign_width: usize = if (value < 0)
        1
    else
        @intFromBool(sign);
    // '0x' or ''
    const prefix_width: usize = if (alternative and base == 16)
        2
    else
        0;
    // full integer
    const content_width: usize = number_width + sign_width + prefix_width;
    // the extra ' ' or '0' characters
    const padding_width: usize = if (min_width) |_min_width|
        _min_width -| content_width
    else
        0;

    if (!left_justified) {
        try writer.writeByteNTimes(if (space) ' ' else if (leading_zeros) '0' else ' ', padding_width);
    }

    if (sign and value >= 0) {
        try writer.writeByte('+');
    } else if (value < 0) {
        try writer.writeByte('-');
    }

    if (alternative and base == 16 and case == .lower) {
        try writer.writeAll("0x");
    } else if (alternative and base == 16 and case == .upper) {
        try writer.writeAll("0X");
    }

    var int_buf: [1 + @max(@as(comptime_int, @typeInfo(@TypeOf(abs_value)).int.bits), 1)]u8 = undefined;
    const int_str_len = std.fmt.formatIntBuf(&int_buf, abs_value, base, case, .{});
    const int_str = int_buf[0..int_str_len];

    const leading_zero_width: usize = number_width - int_str.len;
    try writer.writeByteNTimes('0', leading_zero_width);
    try writer.writeAll(int_str);

    if (left_justified) {
        try writer.writeByteNTimes(if (space) ' ' else if (leading_zeros) '0' else ' ', padding_width);
    }
}

fn fmtOptions(
    left_justified: bool,
    space: bool,
    leading_zeros: bool,
    min_width: ?usize,
    precision: ?usize,
) std.fmt.FormatOptions {
    return .{
        .alignment = if (left_justified) .left else .right,
        .fill = if (space) ' ' else if (leading_zeros) '0' else ' ',
        .precision = precision orelse 1,
        .width = if (!space and !leading_zeros) null else min_width,
    };
}

fn readSignedIntInput(
    length_modifier: LengthModifier,
    args: *std.builtin.VaList,
) !i128 {
    return switch (length_modifier) {
        .hh => @cVaArg(args, i8),
        .h => @cVaArg(args, c_short),
        .none => @cVaArg(args, c_int),
        .l => @cVaArg(args, c_long),
        .ll => @cVaArg(args, c_longlong),
        .j => @cVaArg(args, i128),
        .z => @cVaArg(args, isize),
        .t => @cVaArg(args, i128),
        .L => return abi.sys.Error.InvalidArgument,
    };
}

fn readUnsignedIntInput(
    length_modifier: LengthModifier,
    args: *std.builtin.VaList,
) !u128 {
    return switch (length_modifier) {
        .hh => @cVaArg(args, u8),
        .h => @cVaArg(args, c_ushort),
        .none => @cVaArg(args, c_uint),
        .l => @cVaArg(args, c_ulong),
        .ll => @cVaArg(args, c_ulonglong),
        .j => @cVaArg(args, u128),
        .z => @cVaArg(args, usize),
        .t => @cVaArg(args, u128),
        .L => return abi.sys.Error.InvalidArgument,
    };
}

fn fmtPopChar(fmt: *[]const u8) ?u8 {
    if (fmt.*.len == 0) return null;
    const ch = fmt.*[0];
    fmt.* = fmt.*[1..];
    return ch;
}

pub export fn vfprintf(stream: ?*File, format: [*c]const u8, args: *std.builtin.VaList) callconv(.c) c_int {
    // abi.sys.log("vfprintf()");
    const s = stream orelse return 0;
    const buf_writer = &(s.write orelse return 0);

    const count = vaPrintf(
        buf_writer.writer(),
        format,
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

    buf_writer.flush() catch |err| switch (err) {
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
    // abi.sys.log("printf()");
    var args = @cVaStart();
    defer @cVaEnd(&args);
    return vprintf(format, &args);
}

pub export fn vprintf(format: [*c]const u8, args: *std.builtin.VaList) callconv(.c) c_int {
    // abi.sys.log("vprintf()");
    return vfprintf(stdout, format, args);
}

pub export fn snprintf(s: [*c]u8, n: c_ulong, format: [*c]const u8, ...) callconv(.c) c_int {
    // abi.sys.log("snprintf()");
    var args = @cVaStart();
    defer @cVaEnd(&args);
    return vsnprintf(s, n, format, &args);
}

test "snprintf" {
    var buf = [_]u8{8} ** 64;
    var result = snprintf(&buf, 64, "testing-%s", "123");
    var slice = buf[0 .. @as(usize, @intCast(result)) + 1];
    try std.testing.expectEqualSlices(u8, "testing-123\x00", slice);

    result = snprintf(&buf, 64, "STCFN%.3d", @as(c_int, 33));
    slice = buf[0 .. @as(usize, @intCast(result)) + 1];
    try std.testing.expectEqualSlices(u8, "STCFN033\x00", slice);

    result = snprintf(&buf, 64, "STCFN%03d", @as(c_int, 33));
    slice = buf[0 .. @as(usize, @intCast(result)) + 1];
    try std.testing.expectEqualSlices(u8, "STCFN033\x00", slice);

    result = snprintf(&buf, 64, "STCFN% 3d", @as(c_int, 33));
    slice = buf[0 .. @as(usize, @intCast(result)) + 1];
    try std.testing.expectEqualSlices(u8, "STCFN 33\x00", slice);

    result = snprintf(&buf, 64, "%2.2d", @as(c_int, -4));
    slice = buf[0 .. @as(usize, @intCast(result)) + 1];
    try std.testing.expectEqualSlices(u8, "-04\x00", slice);
}

pub export fn vsnprintf(s: [*c]u8, n: c_ulong, format: [*c]const u8, args: *std.builtin.VaList) callconv(.c) c_int {
    // abi.sys.log("vsnprintf()");
    if (n == 0) return 0;

    var fixed_stream = std.io.fixedBufferStream(s[0 .. n - 1]);
    var overflowing_stream = overflowingWriter(fixed_stream.writer());

    const count = vaPrintf(
        overflowing_stream.writer(),
        format,
        args,
    ) catch |err| {
        errno.errno = errno.asErrno(@errorCast(err));
        return -1;
    };
    s[@min(n - 1, count)] = '\x00';

    return @intCast(count);
}

fn OverflowingWriter(comptime WriterType: type) type {
    return struct {
        child_stream: ?WriterType,

        pub const Error = error{};
        pub const Writer = std.io.Writer(*Self, Error, write);

        const Self = @This();

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            if (self.child_stream) |stream| {
                const amt = stream.write(bytes) catch {
                    self.child_stream = null;
                    return bytes.len;
                };
                return amt;
            }
            return bytes.len;
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
    };
}

fn overflowingWriter(child_stream: anytype) OverflowingWriter(@TypeOf(child_stream)) {
    return .{ .child_stream = child_stream };
}

pub export fn sscanf(s: [*c]const u8, format: [*c]const u8, ...) callconv(.c) c_int {
    // abi.sys.log("sscanf()");
    var args = @cVaStart();
    defer @cVaEnd(&args);
    return vsscanf(s, format, &args);
}

pub export fn vsscanf(s: [*c]const u8, format: [*c]const u8, args: *std.builtin.VaList) callconv(.c) c_int {
    // abi.sys.log("vsscanf()");
    _ = s; // autofix
    _ = format; // autofix
    _ = args; // autofix
    unreachable;
}

pub fn unixPathAsUri(pathname: []const u8) !abi.fs.Path {
    var path: abi.caps.Frame = undefined;
    var path_len: usize = undefined;
    if (std.fs.path.isAbsolute(pathname)) {
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
    // abi.sys.log("fopen()");
    const filename_str: []const u8 = std.mem.span(filename);
    const mode_str: []const u8 = std.mem.span(mode);

    // std.log.info("fopen({s}, {s})", .{ filename_str, mode_str });
    // defer std.log.info("fopen({s}, {s}) done ({})", .{ filename_str, mode_str, errno.errno });

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
    // abi.sys.log("fread()");
    const s = stream orelse return 0;
    const read = &(s.read orelse return 0);

    // std.log.debug("fread size={} count={}", .{ size, count });

    const len: usize = size * count;
    const buffer = @as([*]u8, @ptrCast(ptr))[0..len];

    // FIXME: read UP TO size*count but in multiples of size
    const read_len = read.unbuffered_reader.read( // .readAll(
        buffer,
    ) catch |err| switch (err) {
        error.InvalidState => {
            errno.errno = errno.asErrno(abi.sys.Error.BadHandle);
            return 0;
        },
        error.Full => unreachable,
        else => {
            errno.errno = errno.asErrno(@errorCast(err));
            return 0;
        },
    };

    if (s.write) |*write| switch (write.unbuffered_writer.self.*) {
        .file => |*file| {
            file.cursor.raw += read_len;
        },
        else => {},
    };

    return count;
}

pub export fn fwrite(ptr: ?*const anyopaque, size: c_ulong, count: c_ulong, stream: ?*File) callconv(.c) c_ulong {
    // abi.sys.log("fwrite()");
    _ = ptr; // autofix
    _ = size; // autofix
    _ = count; // autofix
    _ = stream; // autofix
    unreachable;
}

pub export fn fseek(stream: ?*File, offset: c_long, origin: c_int) callconv(.c) c_int {
    // abi.sys.log("fseek()");
    const s = stream orelse return 0;
    // std.log.debug("fseek offset={} origin={}", .{ offset, origin });

    if (fflush(stream) != 0)
        return -1;

    if (s.reader) |*reader| switch (reader.*) {
        .file => |*f| switch (origin) {
            seek_cur => {
                if (offset < 0) {
                    f.cursor.raw -= @abs(offset);
                } else {
                    f.cursor.raw += @abs(offset);
                }
            },
            seek_end => {
                const size = f.frame.getSize() catch unreachable;
                if (offset < 0) {
                    f.cursor.raw = size - @abs(offset);
                } else {
                    f.cursor.raw = size;
                }
            },
            seek_set => {
                if (offset < 0) {
                    f.cursor.raw = 0;
                } else {
                    f.cursor.raw = @intCast(offset);
                }
            },
            else => {
                errno.errno = errno.asErrno(abi.sys.Error.InvalidArgument);
                return -1;
            },
        },
        else => return 0,
    };
    if (s.writer) |*writer| switch (writer.*) {
        .file => |*f| switch (origin) {
            seek_cur => {
                if (offset < 0) {
                    f.cursor.raw -= @abs(offset);
                } else {
                    f.cursor.raw += @abs(offset);
                }
            },
            seek_end => {
                const size = f.frame.getSize() catch unreachable;
                if (offset < 0) {
                    f.cursor.raw = size - @abs(offset);
                } else {
                    f.cursor.raw = size;
                }
            },
            seek_set => {
                if (offset < 0) {
                    f.cursor.raw = 0;
                } else {
                    f.cursor.raw = @intCast(offset);
                }
            },
            else => {
                errno.errno = errno.asErrno(abi.sys.Error.InvalidArgument);
                return -1;
            },
        },
        else => return 0,
    };
    return 0;
}

pub export fn ftell(stream: ?*File) callconv(.c) c_long {
    // abi.sys.log("ftell()");
    const s = stream orelse return 0;

    if (s.reader) |reader| switch (reader) {
        .file => |f| {
            // std.log.debug("ftell 0x{x}", .{f.cursor.raw});
            return @intCast(f.cursor.raw);
        },
        else => return 0,
    };
    if (s.writer) |writer| switch (writer) {
        .file => |f| {
            // std.log.debug("ftell 0x{x}", .{f.cursor.raw});
            return @intCast(f.cursor.raw);
        },
        else => return 0,
    };
    return 0;
}

pub export fn fflush(stream: ?*File) callconv(.c) c_int {
    // abi.sys.log("fflush()");
    const s = stream orelse return 0;

    if (s.write) |*write| {
        write.flush() catch |err| {
            errno.errno = errno.asErrno(@errorCast(err));
            return -1;
        };
    }

    if (s.read) |*read| {
        // destroy buffered contents
        read.start = 0;
        read.end = 0;
    }

    return 0;
}

pub export fn fclose(stream: ?*File) callconv(.c) c_int {
    // abi.sys.log("fclose()");
    const s = stream orelse return 0;
    if (s.file) |file| file.close();
    return 0;
}

pub export fn rename(old_filename: [*c]const u8, new_filename: [*c]const u8) callconv(.c) c_int {
    // abi.sys.log("rename()");
    _ = old_filename; // autofix
    _ = new_filename; // autofix
    unreachable;
}

pub export fn remove(pathname: [*c]const u8) callconv(.c) c_int {
    // abi.sys.log("remove()");
    _ = pathname; // autofix
    unreachable;
}
